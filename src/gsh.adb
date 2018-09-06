------------------------------------------------------------------------------
--                                                                          --
--                                  G S H                                   --
--                                                                          --
--                                                                          --
--                       Copyright (C) 2010-2018, AdaCore                   --
--                                                                          --
-- GSH is free software;  you can  redistribute it  and/or modify it under  --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GSH is distributed in the hope that it will be useful, but WITH-  --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the  Free Software Foundation,  51  Franklin  Street,  Fifth  Floor, --
-- Boston, MA 02110-1301, USA.                                              --
--                                                                          --
-- GSH is maintained by AdaCore (http://www.adacore.com)                    --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions; use Ada.Exceptions;
with Ada.Directories; use Ada.Directories;
with GNAT.OS_Lib; use GNAT.OS_Lib;
with GNAT.Ctrl_C;
with Posix_Shell.Lexer; use Posix_Shell.Lexer;
with Posix_Shell.Parser; use Posix_Shell.Parser;
with Posix_Shell.Tree; use Posix_Shell.Tree;
with Posix_Shell.Tree.Evals; use Posix_Shell.Tree.Evals;
with Posix_Shell.Variables; use Posix_Shell.Variables;
with Posix_Shell.Variables.Output; use Posix_Shell.Variables.Output;
with Posix_Shell.Exec; use Posix_Shell.Exec;
with Posix_Shell.Opts; use Posix_Shell.Opts;
with Posix_Shell.Builtins; use Posix_Shell.Builtins;
with Posix_Shell.Utils; use Posix_Shell.Utils;
with Posix_Shell; use Posix_Shell;
with Posix_Shell.Tree.Dumps; use Posix_Shell.Tree.Dumps;

---------
-- GSH --
---------

function GSH return Integer is
   T             : Shell_Tree;
   Status        : Integer := 0;
   State         : Shell_State;
   Script_Buffer : Buffer_Access := null;

   procedure Null_Procedure;
   --  null procedure used for the default Ctrl-C handler in interactive
   --  mode

   --------------------
   -- Null_Procedure --
   --------------------

   procedure Null_Procedure is
   begin
      null;
   end Null_Procedure;

begin
   --  Import into our state the current process environment
   Import_Environment (State);

   declare
      Current_Dir    : constant String := Get_Current_Dir (State, True);
      Is_Interactive : Boolean;
      Should_Exit    : Boolean := False;

   begin
      --  Reset PWD and OLDPWD in order to avoid inheriting the values
      --  from the parent process.
      Set_Var_Value (State, "PWD", Current_Dir, Export => True);
      Set_Var_Value (State, "OLDPWD", Current_Dir, Export => True);
      Set_Var_Value (State, "IFS", " " & ASCII.HT & ASCII.LF);
      Set_Var_Value (State, "PATH_SEPARATOR", ":");

      --  Disable auto expansion of parameters by the cygwin programs. Indeed
      --  when a cygwin program is called outside a cygwin shell, it will try
      --  to perform expansions on the parameters such as filename expansion.
      --  As this is provided by gsh we do not want the parameter to be
      --  expanded twice
      declare
         Cygwin : constant String := Get_Var_Value (State, "CYGWIN");

      begin
         if Cygwin = "" then
            Set_Var_Value
              (State, "CYGWIN", "noglob", Export => True);

         else
            Set_Var_Value
              (State, "CYGWIN",
               Get_Var_Value (State, "CYGWIN") & " noglob",
               Export => True);
         end if;
      end;

      --  Set the last exit status to zero, so that the first command
      --  in the script can access it (if the first command is "echo $?",
      --  for instance).
      Save_Last_Exit_Status (State, 0);

      --  Process the command line and in case of usage error exit
      Process_Command_Line (State, Script_Buffer, Status, Is_Interactive);
      if Status /= 0 then
         return Status;
      end if;

      if Is_Interactive then
         GNAT.Ctrl_C.Install_Handler (Null_Procedure'Unrestricted_Access);
      end if;

      --  The shell main loop
      loop
         if Is_Interactive then
            Set_Directory (Get_Var_Value (State, "PWD"));
            declare
               Line : constant String := Readline ("$ ");
            begin
               --  This buffer is freed when deallocating the AST.
               Script_Buffer :=
                 new Token_Buffer'(New_Buffer (Line));
            end;
         end if;

         T := Parse_Buffer (Script_Buffer.all);

         if Dump_Node_Table then
            Dump (T);
         end if;

         --  If -n was passed skip evaluation of the script.
         if Do_Script_Evaluation then

            begin
               Eval (State, T);
               Status := Get_Last_Exit_Status (State);

            exception
               when Shell_Exit_Exception =>
                  Status := Get_Last_Exit_Status (State);
                  Should_Exit := True;

               when Shell_Return_Exception =>
                  Put
                    (State, 2,
                     "return: can only `return' from a " &
                       "function or sourced script" & ASCII.LF);
                  Save_Last_Exit_Status (State, 1);
                  Status := 1;

            end;

            --  Do we have a trap registered ?
            if not Is_Interactive or else Should_Exit then
               declare
                  Exit_Trap_Action : constant String_Access :=
                    Get_Trap_Action (State, 0);
                  Trap_Status : Integer;
                  pragma Warnings (Off, Trap_Status);

               begin

                  if Exit_Trap_Action /= null and then
                    Exit_Trap_Action.all'Length > 0
                  then
                     Trap_Status := Execute_Builtin (State,
                                                     "eval",
                                                     (1 => Exit_Trap_Action));
                  end if;
               exception
                  when Shell_Exit_Exception =>
                     Status := Get_Last_Exit_Status (State);
                     exit;
                  when Shell_Return_Exception =>
                     Put
                       (State, 2,
                        "return: can only `return' from a " &
                          "function or sourced script" & ASCII.LF);
                     Save_Last_Exit_Status (State, 1);
                     Status := 1;
               end;
            end if;
         end if;

         Free_Node (T);

         --  We should exit if an exit command was emited or when not in
         --  interactive mode once the scripts execution is complete.
         if not Is_Interactive or Should_Exit then
            exit;
         end if;
      end loop;

      return Status;

   exception
      when E : Shell_Syntax_Error | Shell_Non_Implemented |
           Shell_Lexer_Error =>
         Put_Line (Exception_Message (E));
         return 127;
   end;

end GSH;
