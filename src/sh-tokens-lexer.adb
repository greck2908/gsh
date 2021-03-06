------------------------------------------------------------------------------
--                                                                          --
--                                  G S H                                   --
--                                                                          --
--                                                                          --
--                       Copyright (C) 2010-2016, AdaCore                   --
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

with Ada.Unchecked_Deallocation;
with Ada.Exceptions; use Ada.Exceptions;
with Sh.String_Utils; use Sh.String_Utils;
with Sh.Traces; use Sh.Traces;

package body Sh.Tokens.Lexer is

   procedure Lexer_Error (B : in out Token_Buffer; Msg : String);
   --  Report an error.

   function Get_Char (B : in out Token_Buffer) return Character;
   pragma Inline (Get_Char);
   --  Get the next char from the buffer and update the buffer state.

   procedure Unget_Char (B : in out Token_Buffer);
   pragma Inline (Unget_Char);
   --  Undo last Get_Char.

   procedure Pushback (B : in out Token_Buffer; T : Token);
   pragma Inline (Pushback);
   --  Cancel effect of last Read_Token call.

   function Read_IOHere
     (B      : in out Token_Buffer;
      Marker : Token)
      return Token;
   --  Read IO Here content

   function Read_Token_Aux
     (B      : in out Token_Buffer;
      IOHere : Boolean := False)
      return Token;

   function Read_Command_Token_Aux (Tk : Token) return Token;

   procedure Deallocate (B : in out Buffer_Access) is
      procedure Internal_Free is
        new Ada.Unchecked_Deallocation
          (Token_Buffer,
           Buffer_Access);
   begin
      Deallocate (B.Content);
      B.Content := Null_Buffer;
      Internal_Free (B);
   end Deallocate;

   procedure Deallocate (B : in out Token_Buffer) is
   begin
      Deallocate (B.Content);
   end Deallocate;

   ------------------
   -- Expect_Token --
   ------------------

   procedure Expect_Token
     (B   : in out Token_Buffer;
      T   : Token_Type;
      Msg : String := "")
   is
      Next : constant Token := Read_Command_Token (B);
   begin
      if Next.Kind /= T then
         if Msg'Length = 0 then
            Syntax_Error (Next, "expect token '" & Image (T) & "'");
         else
            Syntax_Error (Next, Msg);
         end if;
      end if;
   end Expect_Token;

   ----------------
   -- Get_Buffer --
   ----------------

   function Get_Buffer (B : Token_Buffer) return Buffer
   is
   begin
      return B.Content;
   end Get_Buffer;

   --------------
   -- Get_Char --
   --------------

   function Get_Char (B : in out Token_Buffer) return Character is
      Tmp : constant Character := Current (B.Content);
   begin
      Forward (B.Content);
      return Tmp;
   end Get_Char;

   ------------------
   -- Lexer_Error --
   ------------------

   procedure Lexer_Error (B : in out Token_Buffer; Msg : String) is
   begin
      Raise_Exception
        (Shell_Lexer_Error'Identity, Image (Current (B.Content), Msg));
   end Lexer_Error;

   ---------------
   -- Lookahead --
   ---------------

   function Lookahead (B : in out Token_Buffer) return Token_Type is
      T : constant Token := Read_Token (B);
   begin
      Pushback (B, T);
      return T.Kind;
   end Lookahead;

   -----------------------
   -- Lookahead_Command --
   -----------------------

   function Lookahead_Command (B : in out Token_Buffer) return Token_Type is
   --  T : constant Token := Read_Command_Token (B);
      T      : constant Token := Read_Token (B);
      Result : constant Token := Read_Command_Token_Aux (T);
   begin
      Pushback (B, T);
      return Result.Kind;
   end Lookahead_Command;

   ----------------
   -- New_Buffer --
   ----------------

   function New_Buffer (Str : String) return Token_Buffer is
      Result : Token_Buffer;
   begin
      Result.Content := New_Buffer (Str);
      Result.Pushback_Loc := Current (Result.Content);
      Result.Cache_Loc := Current (Result.Content);
      Result.Valid_Cache := False;
      return Result;
   end New_Buffer;

   --------------------------
   -- New_Buffer_From_File --
   --------------------------

   function New_Buffer_From_File (Filename : String) return Token_Buffer is
      Result : Token_Buffer;
   begin
      Result.Content := New_Buffer_From_File (Filename);
      Result.Pushback_Loc := Current (Result.Content);
      Result.Cache_Loc := Current (Result.Content);
      Result.Valid_Cache := False;
      Result.Next_Is_Marker := False;
      return Result;
   end New_Buffer_From_File;

   --------------
   -- Pushback --
   --------------

   procedure Pushback (B : in out Token_Buffer; T : Token) is
   begin

      B.Cache_Loc := Current (B.Content);
      B.Cache_Token := T;
      B.Valid_Cache := True;
      Seek (B.Content, B.Pushback_Loc);
      pragma Debug (Log (LOG_LEXER, "pushback"));
   end Pushback;

   ------------------------
   -- Read_Command_Token --
   ------------------------

   function Read_Command_Token (B : in out Token_Buffer) return Token is
      T      : constant Token := Read_Token (B);
      Result : constant Token := Read_Command_Token_Aux (T);

   begin
      pragma Debug (Log (LOG_LEXER, "cmd token: " & Image (Result)));
      return Result;
   end Read_Command_Token;

   ----------------------------
   -- Read_Command_Token_Aux --
   ----------------------------

   function Read_Command_Token_Aux (Tk : Token) return Token is
      T : Token := Tk;

      function New_Token (TT : Token_Type) return Token;
      --  Return a new token of type TT with no string attached

      function Is_Assignment (Expr : String) return Boolean;
      --  Return True if the given expression (Expr) is an assignment.

      function To_Word (S : String) return String;
      --  To improve memory usage, token are simply references to the script
      --  buffer. As a consequence we differ a bit from what's expected in
      --  the standard (2.2.1 Escape character) and backslashes followed by
      --  <newline> are not removed from the tokens. To_Word removes them.

      -------------------
      -- Is_Assignment --
      -------------------

      function Is_Assignment (Expr : String) return Boolean is
      begin
         for J in Expr'Range loop
            if Expr (J) = '=' then

               --  We have a possible assignment.  Check the name
               --  of the target variable:  If it is a valid name,
               --  then indeed we have an actual assignment. Otherwise,
               --  this equal sign is part of something else, for
               --  instance a quote string, or a command name.

               return Is_Valid_Variable_Name (Expr (Expr'First .. J - 1));
            end if;
         end loop;

         return False;
      end Is_Assignment;

      ---------------
      -- New_Token --
      ---------------

      function New_Token (TT : Token_Type) return Token is
      begin
         return (TT, T.First, T.Last, T.Content);
      end New_Token;

      -------------
      -- To_Word --
      -------------

      function To_Word (S : String) return String is
         Result : String (1 .. S'Length);
         Result_Last : Natural := 0;
         Index : Integer := S'First;
      begin
         loop
            exit when Index > S'Last;
            if Index < S'Last and then S (Index) = '\' and then
              S (Index + 1) = ASCII.LF
            then
               Index := Index + 1;
            else
               Result_Last := Result_Last + 1;
               Result (Result_Last) := S (Index);
            end if;
            Index := Index + 1;
         end loop;
         return Result (1 .. Result_Last);
      end To_Word;

   begin
      if T.Kind = T_WORD then
         declare
            Raw : constant String := Slice (T.Content, T.First, T.Last);
            S   : constant String := To_Word (Raw);

         begin
            if S = "if"       then
               T := New_Token (T_IF);
            elsif S = "then"  then
               T := New_Token (T_THEN);
            elsif S = "else"  then
               T := New_Token (T_ELSE);
            elsif S = "elif"  then
               T := New_Token (T_ELIF);
            elsif S = "fi"    then
               T := New_Token (T_FI);
            elsif S = "do"    then
               T := New_Token (T_DO);
            elsif S = "done"  then
               T := New_Token (T_DONE);
            elsif S = "case"  then
               T := New_Token (T_CASE);
            elsif S = "esac"  then
               T := New_Token (T_ESAC);
            elsif S = "while" then
               T := New_Token (T_WHILE);
            elsif S = "until" then
               T := New_Token (T_UNTIL);
            elsif S = "for"   then
               T := New_Token (T_FOR);
            elsif S = "in"    then
               T := New_Token (T_IN);
            elsif S = "{"     then
               T := New_Token (T_LBRACE);
            elsif S = "}"     then
               T := New_Token (T_RBRACE);
            elsif S = "!"     then
               T := New_Token (T_BANG);
            elsif Is_Assignment (S) then
               T.Kind := T_ASSIGNEMENT;
            end if;
         end;
      end if;

      return T;
   end Read_Command_Token_Aux;

   -----------------
   -- Read_IOHere --
   -----------------

   function Read_IOHere
     (B      : in out Token_Buffer;
      Marker : Token)
      return Token
   is
      CC               : Character;
      Raw_Marker       : constant String := Tokens.As_String (Marker);
      Real_Marker      : String (1 .. Raw_Marker'Length);
      Real_Marker_Last : Integer := 0;
      Token_Start      : Text_Position;
      In_Single_Quote  : Boolean := False;
      In_Double_Quote  : Boolean := False;
      Index            : Integer := Raw_Marker'First;
      Here_Doc_Kind    : Token_Type := T_HERE_DOC;
   begin
      --  Check if we should consider parameter expansion in the IO Here
      --  document.
      loop
         case Raw_Marker (Index) is
            when '\' =>
               if not In_Single_Quote then
                  Here_Doc_Kind := T_HERE_DOC_PLAIN;
                  if not In_Double_Quote or else
                    Raw_Marker (Index) = '"' or else
                    Raw_Marker (Index) = '`' or else
                    Raw_Marker (Index) = '$' or else
                    Raw_Marker (Index) = '\'
                  then
                     Index := Index + 1;
                  end if;
               end if;
               Real_Marker_Last := Real_Marker_Last + 1;
               Real_Marker (Real_Marker_Last) := Raw_Marker (Index);
            when ''' =>
               Here_Doc_Kind := T_HERE_DOC_PLAIN;
               if In_Single_Quote then
                  In_Single_Quote := False;
               elsif not In_Double_Quote then
                  In_Single_Quote := True;
               end if;
            when '"' =>
               Here_Doc_Kind := T_HERE_DOC_PLAIN;
               if In_Double_Quote then
                  In_Double_Quote := False;
               elsif not In_Single_Quote then
                  In_Double_Quote := True;
               end if;
            when others =>
               Real_Marker_Last := Real_Marker_Last + 1;
               Real_Marker (Real_Marker_Last) := Raw_Marker (Index);
         end case;
         Index := Index + 1;
         exit when Index > Raw_Marker'Last;
      end loop;

      --  First skip everything until new line
      --  while Get_Char (B) /= ASCII.LF loop
      --   null;
      --  end loop;

      Token_Start := Current (B.Content);

      CC := ASCII.LF;

      loop
         case CC is
            when ASCII.LF =>
               if Current (B.Content, Real_Marker_Last + 1) =
                 Real_Marker (1 .. Real_Marker_Last) & ASCII.LF

               then
                  declare
                     T : constant Token := (Here_Doc_Kind, Token_Start,
                                            Previous (B.Content), B.Content);
                  begin
                     CC := Get_Char (B);

                     while CC /= ASCII.LF loop
                        CC := Get_Char (B);
                     end loop;
                     Unget_Char (B);
                     return T;
                  end;
               end if;

            when ASCII.EOT =>
               Unget_Char (B);
               return (Here_Doc_Kind, Token_Start, Previous (B.Content),
                       B.Content);

            when others =>
               null;
         end case;
         CC := Get_Char (B);
      end loop;
   end Read_IOHere;

   ----------------
   -- Read_Token --
   ----------------

   function Read_Token (B : in out Token_Buffer) return Token is
      Result : Token;
   begin
      if B.Valid_Cache then
         Seek (B.Content, B.Cache_Loc);
         B.Valid_Cache := False;
         Result := B.Cache_Token;
      else
         Result := Read_Token_Aux (B);
      end if;

      pragma Debug (Log (LOG_LEXER, "token:" & Image (Result)));
      return Result;
   end Read_Token;

   function Read_Token (B : in out Token_Buffer) return Token_Type is
      T : constant Token := Read_Token (B);
   begin
      return T.Kind;
   end Read_Token;

   function Read_Token (B : in out Token_Buffer) return String is
      T : constant Token := Read_Token (B);
   begin
      return Slice (T.Content, T.First, T.Last);
   end Read_Token;

   --------------------
   -- Read_Token_Aux --
   --------------------

   function Read_Token_Aux
     (B      : in out Token_Buffer;
      IOHere : Boolean := False)
      return Token
   is

      --  Buffer containing the current token chars

      Token_Start        : Text_Position;

      Has_Token        : Boolean := False;
      --  True if token recognition has started

      --  Current_Line     : constant Integer := Current_Lineno (B.B);
      --  Current_Column   : Integer := Current_Columnno (B.B);
      --  Pos : Text_Position := Current_Pos (B.B);

      CC               : Character;

      function Return_Token (T : Token_Type := T_WORD) return Token;
      pragma Inline (Return_Token);

      procedure Read_Escape_Sequence
        (Skip_Mode       : Boolean;
         In_Double_Quote : Boolean);

      procedure Read_Single_Quote;
      procedure Read_Double_Quote (Skip_Mode : Boolean);

      procedure Read_Command_Substitution
        (In_Double_Quote : Boolean);
      procedure Read_Backquote_Command_Substitution;

      procedure Read_Arithmetic_Expansion;

      procedure Read_Parameter_Evaluation (Skip_Mode : Boolean);

      procedure Read_Dollar_Substitution
        (Skip_Mode       : Boolean;
         In_Double_Quote : Boolean);

      -----------------------------------------
      -- Read_Backquote_Command_Substitution --
      -----------------------------------------

      procedure Read_Backquote_Command_Substitution
      is
      begin
         Has_Token := True;

         loop
            CC := Get_Char (B);
            case CC is
               when '\' =>
                  CC := Get_Char (B);
               when '`' =>
                  exit;
               when ASCII.EOT =>
                  Lexer_Error
                    (B, "unexpected EOF while looking for matching '`'");
               when others =>
                  null;
            end case;
         end loop;
      end Read_Backquote_Command_Substitution;

      -------------------------------
      -- Read_Command_Substitution --
      -------------------------------

      procedure Read_Command_Substitution
        (In_Double_Quote : Boolean)
      is
      begin
         pragma Assert (CC = '$');

         CC := Get_Char (B);

         pragma Assert (CC = '(');

         loop
            CC := Get_Char (B);
            case CC is
               when '\' => Read_Escape_Sequence
                    (Skip_Mode => True, In_Double_Quote => False);
               when '`' => Read_Backquote_Command_Substitution;
               when '$' => Read_Dollar_Substitution
                    (Skip_Mode => True, In_Double_Quote => In_Double_Quote);
               when '"' => Read_Double_Quote
                    (Skip_Mode => True);
               when ''' => Read_Single_Quote;

               when '#' =>
                  while Get_Char (B) /= ASCII.LF loop null; end loop;
                  Unget_Char (B);
               when ')' =>
                  exit;
               when others =>
                  null;
            end case;
         end loop;
      end Read_Command_Substitution;

      -------------------------------
      -- Read_Arithmetic_Expansion --
      -------------------------------

      procedure Read_Arithmetic_Expansion is
         Opened_Paranthesis : Natural := 2;
         Previous_Was_Par   : Boolean := False;
      begin
         pragma Assert (CC = '$');

         CC := Get_Char (B);
         pragma Assert (CC = '(');

         CC := Get_Char (B);
         pragma Assert (CC = '(');

         loop
            CC := Get_Char (B);

            case CC is
               when '(' => Opened_Paranthesis := Opened_Paranthesis + 1;
               when ')' =>
                  Opened_Paranthesis := Opened_Paranthesis - 1;
                  if Opened_Paranthesis = 0 and Previous_Was_Par then
                     exit;
                  end if;
               when '$' =>
                  Read_Dollar_Substitution
                    (Skip_Mode => False, In_Double_Quote => False);
               when '`' => Read_Backquote_Command_Substitution;
               when ASCII.EOT =>
                     Lexer_Error
                        (B, "unexpected EOF while looking for matchin '))'");
               when others =>
                  null;
            end case;

            Previous_Was_Par := CC = ')';
         end loop;

      end Read_Arithmetic_Expansion;

      -----------------------
      -- Read_Double_Quote --
      -----------------------

      procedure Read_Double_Quote (Skip_Mode : Boolean) is
      begin

         Has_Token := True;

         loop
            CC := Get_Char (B);
            if CC = '"' then
               exit;
            else
               case CC is
                  when '\' => Read_Escape_Sequence
                       (Skip_Mode => Skip_Mode, In_Double_Quote => True);
                  when '`' =>
                     Read_Backquote_Command_Substitution;

                  when '$' => Read_Dollar_Substitution
                       (In_Double_Quote => True, Skip_Mode => Skip_Mode);
                  when ASCII.EOT =>
                     Lexer_Error
                       (B, "unexpected EOF while looking for matchin '""'");
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Read_Double_Quote;

      --------------------------
      -- Read_Escape_Sequence --
      --------------------------

      procedure Read_Escape_Sequence
        (Skip_Mode       : Boolean;
         In_Double_Quote : Boolean)
      is
      begin
         --  Section 2.2.1 Escape Character (\)
         --  A backslash that is not quoted shall preserve the literal
         --  value of the following character, with the exception of a
         --  <newline>. If a <newline> follows the backslash, the shell
         --  shall interpret this as line continuation. The backslash and
         --  <newline>s shall be removed before splitting the input into
         --  tokens. Since the escaped <newline> is removed entirely from
         --  the input and is not replaced by any white space, it cannot
         --  serve as a token separator.

         CC := Get_Char (B);

         if CC /= ASCII.LF then
            --  This also refer implicitely to Section 2.3 Rule 11
            Has_Token := True;
            if not Skip_Mode then
               if not In_Double_Quote or else CC = '"' or else CC = '`' or else
                 CC = '$' or else CC = '\'
               then
                  null;
               else
                  Unget_Char (B);
               end if;
            else
               null;
            end if;
            --  Add_To_Token (CC);
         elsif not Has_Token then
            Token_Start := Current (B.Content);
         end if;
      end Read_Escape_Sequence;

      -----------------------------------
      -- Read_Dollar_Substitution --
      -----------------------------------

      procedure Read_Dollar_Substitution
        (Skip_Mode       : Boolean;
         In_Double_Quote : Boolean)
      is
         pragma Unreferenced (In_Double_Quote);
         Is_Arithmetic_Expansion : Boolean := False;

      begin
         Has_Token := True;
         CC := Get_Char (B);

         if CC = '(' then
            CC := Get_Char (B);
            Is_Arithmetic_Expansion := CC = '(';

            Unget_Char (B);
            Unget_Char (B);
            CC := '$';

            if Is_Arithmetic_Expansion then
               --  if $ is followed by (( then it's an arithmetic expression
               --  that is to be expanded.
               Read_Arithmetic_Expansion;
            else
               --  if $ is followed by a unique ( it's actually a command
               --  substitution.
               Read_Command_Substitution (In_Double_Quote => False);
            end if;
         else
            Unget_Char (B);
            CC := '$';
            Read_Parameter_Evaluation (Skip_Mode);
         end if;
      end Read_Dollar_Substitution;

      -------------------------------
      -- Read_Parameter_Evaluation --
      -------------------------------

      procedure Read_Parameter_Evaluation (Skip_Mode : Boolean)
      is
      begin
         pragma Assert (CC = '$');

         CC := Get_Char (B);

         --  Check the first character following the '$' sign.
         --  If it is a paramater evaluation, then only a few selected
         --  characters can follow it.  Otherwise, the $ sign is just
         --  a token on its own.

         if not (CC in 'a' .. 'z'
                 or else CC in 'A' .. 'Z'
                 or else CC in '0' .. '9'
                 or else CC = '{'
                 or else CC = '_'
                 or else CC = '@'
                 or else CC = '*'
                 or else CC = '#'
                 or else CC = '?'
                 or else CC = '-'
                 or else CC = '$'
                 or else CC = '!')
         then
            Unget_Char (B);
            return;
         end if;

         --  This parameter is indeed the first character of a parameter
         --  name, and thus the '$' sign is indeed the start of a parameter
         --  evaluation.

         --  If the '$' is followed by '{', then the parameter evaluation
         --  expression ends at the associated enclosing '}'.

         if CC = '{' then
            while CC /= '}' loop
               if CC = '\' then
                  Read_Escape_Sequence
                    (Skip_Mode => Skip_Mode, In_Double_Quote => False);
               elsif CC = '"' then
                  Read_Double_Quote (Skip_Mode => Skip_Mode);
               elsif CC = ''' then
                  Read_Single_Quote;
               elsif CC = '`' then
                  Read_Backquote_Command_Substitution;

               elsif CC = '$' then
                  Read_Dollar_Substitution
                    (Skip_Mode => Skip_Mode, In_Double_Quote => False);
               else
                  null;
               end if;
               CC := Get_Char (B);
            end loop;
            return;
         end if;

         --  Is this a positional or special parameter? In such case,
         --  the token ends at the first character.

         if CC in '0' .. '9' --  Positional parameter
           or else CC = '@'  --  Special parameter
           or else CC = '*'  --  Special parameter
           or else CC = '#'  --  Special parameter
           or else CC = '?'  --  Special parameter
           or else CC = '-'  --  Special parameter
           or else CC = '$'  --  Special parameter
           or else CC = '!'  --  Special parameter
         then
            return;
         end if;

         --  This is a more usual parameter. The token ends when we find
         --  a character that is not valid in a parameter name. Then,
         --  annotate the last valid character as the end of the parameter.

         declare
            Next_Char : Character;
         begin
            loop
               Next_Char := Get_Char (B);
               case Next_Char is
                  when 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' =>
                     null;
                  when others =>
                     Unget_Char (B);
                     return;
               end case;
               CC := Next_Char;
            end loop;
         end;

      end Read_Parameter_Evaluation;

      -----------------------
      -- Read_Single_Quote --
      -----------------------

      procedure Read_Single_Quote is
         Start_Pos : constant Text_Position := Current (B.Content);

      begin
         Has_Token := True;

         loop
            CC := Get_Char (B);

            case CC is
               when ''' =>
                  exit;
               when ASCII.EOT =>
                  Lexer_Error
                    (B,
                     "unexpected EOF in single quote starting at " &
                     Image (Start_Pos));
               when others =>
                  null;
            end case;
         end loop;
      end Read_Single_Quote;

      ------------------
      -- Return_Token --
      ------------------

      function Return_Token (T : Token_Type := T_WORD) return Token
      is
         Result : constant Token := (T,
                                     Token_Start,
                                     Previous (B.Content),
                                     B.Content);
      begin
         if B.Next_Is_Marker then
            B.Next_Is_Marker := False;
            B.Pending_Here_Docs := B.Pending_Here_Docs + 1;
            B.Here_Doc_Stack (B.Pending_Here_Docs) := Result;
         end if;

         if T in T_DLESS .. T_DLESSDASH then
            B.Next_Is_Marker := True;
         end if;

         return Result;
      end Return_Token;

   begin
      --  Save current state of the buffer in case pushback is called afterward
      B.Pushback_Loc := Current (B.Content);
      Token_Start := Current (B.Content);

      --  Check for pending here documents
      if B.Next_Is_Here_Docs then
         declare
            T : Token;
         begin
            T := Read_IOHere (B,
                              B.Here_Doc_Stack (B.Here_Doc_Next));
            B.Here_Doc_Next := B.Here_Doc_Next + 1;
            B.Pending_Here_Docs := B.Pending_Here_Docs - 1;
            if B.Pending_Here_Docs = 0 then
               B.Here_Doc_Next := 1;
            end if;
            B.Next_Is_Here_Docs := False;
            return T;
         end;
      end if;

      loop
         CC := Get_Char (B);

         --  Check if we should delimit the token
         if Has_Token then
            case CC is
               when ASCII.EOT | '(' | ')' | ';' | '&' | '|' | ASCII.LF | ' ' |
                    ASCII.HT =>
                  Unget_Char (B);
                  return Return_Token;

               when '>' | '<' =>
                  Unget_Char (B);
                  if Is_Natural
                    (Slice (B.Content,
                            Token_Start,
                            Previous (B.Content)))
                  then
                     return Return_Token (T_IO_NUMBER);
                  else
                     return Return_Token;
                  end if;
               when others => null;
            end case;
         end if;

         --  [Section 2.3 Rule 2]
         --  If the previous character was used as part of an operator and the
         --  current character is not quoted and can be used with the current
         --  characters to form an operator, it shall be used as part of that
         --  (operator) token.

         --  [Section 2.3 Rule 3]
         --  If the previous character was used as part of an operator and the
         --  current character cannot be used with the current characters to
         --  form an operator, the operator containing the previous character
         --  shall be delimited.

         --  [Section 2.3 Rule 6]
         --  If the current character is not quoted and can be used as the
         --  first character of a new operator, the current token (if any)
         --  shall be delimited. The current character shall be used as the
         --  beginning of the next (operator) token.

         case CC is
            when ASCII.EOT =>
               --  If there is no current token, the end-of-input indicator
               --  shall be returned as the token.
               return Return_Token (T_EOF);
            when '(' =>
               --  [Section 2.3 Rule 3]
               return Return_Token (T_LPAR);

            when ')' =>
               --  [Section 2.3 Rule 3]
               return Return_Token (T_RPAR);

            when ';' =>
               if Get_Char (B) = ';' then
                  --  [Section 2.3 Rule 2]
                  --  [Section 2.3 Rule 3]
                  return Return_Token (T_DSEMI);
               else
                  Unget_Char (B);
                  --  [Section 2.3 Rule 3]
                  return Return_Token (T_SEMI);
               end if;

            when '&' =>

               if Get_Char (B) = '&' then
                  --  [Section 2.3 Rule 2]
                  --  [Section 2.3 Rule 3]
                  return Return_Token (T_AND_IF);
               else
                  Unget_Char (B);
                  --  [Section 2.3 Rule 3]
                  return Return_Token (T_AND);
               end if;

            when '|' =>

               if Get_Char (B) = '|' then
                  return Return_Token (T_OR_IF);
               else
                  Unget_Char (B);
                  return Return_Token (T_PIPE);
               end if;

            when '>' =>

               CC := Get_Char (B);
               case CC is
                  when '>' =>
                     return Return_Token (T_DGREAT);
                  when '|' =>
                     return Return_Token (T_CLOBBER);
                  when '&' =>
                     return Return_Token (T_GREATAND);
                  when others =>
                     Unget_Char (B);
                     return Return_Token (T_GREAT);
               end case;

            when '<' =>
               CC := Get_Char (B);
               case CC is
                  when '<' =>
                     if Get_Char (B) = '-' then
                        return Return_Token (T_DLESSDASH);
                     else
                        Unget_Char (B);
                        return Return_Token (T_DLESS);
                     end if;
                  when '&' =>
                     return Return_Token (T_LESSAND);
                  when '>' =>
                     return Return_Token (T_LESSGREAT);
                  when others =>
                     Unget_Char (B);
                     return Return_Token (T_LESS);
               end case;
            when ASCII.LF =>
               if B.Pending_Here_Docs > 0 then
                  B.Next_Is_Here_Docs := True;
               end if;

               return Return_Token (T_NEWLINE);
            when ' ' | ASCII.HT =>
               --  discard <blank> character
               Token_Start := Current (B.Content);
            when '\' =>
               Read_Escape_Sequence (False, False);
            when '"' =>
               Read_Double_Quote (False);
            when ''' =>
               Read_Single_Quote;
            when '`' =>
               Read_Backquote_Command_Substitution;
               if IOHere then
                  return Return_Token (T_WORD);
               end if;
            when '$' =>
               Read_Dollar_Substitution (False, False);
               if IOHere then
                  return Return_Token (T_WORD);
               end if;
            when others =>
               if CC = '#' and then not Has_Token then
                  --  [Section 2.3. Rule 10]
                  --  If the current character is a '#', it and all subsequent
                  --  characters up to, but excluding, the next <newline> shall
                  --  be discarded as a comment. The <newline> that ends the
                  --  line is not considered part of the comment.

                  declare
                     Tmp_CC : Character := Get_Char (B);
                  begin
                     while Tmp_CC /= ASCII.LF and Tmp_CC /= ASCII.EOT loop
                        Tmp_CC := Get_Char (B);
                     end loop;
                  end;
                  Unget_Char (B);
                  Token_Start := Current (B.Content);
               else
                  --  [Section 2.3 Rule 11]
                  --  The current character is used as the start of a new word.
                  Has_Token := True;

                  --  [Section 2.3 Rule 9]
                  --  If the previous character was part of a word, the current
                  --  character shall be appended to that word.
               end if;
         end case;

      end loop;
   end Read_Token_Aux;

   ---------------------
   -- Read_Word_Token --
   ---------------------

   function Read_Word_Token (B : in out Token_Buffer) return Token is
      Next : constant Token := Read_Token (B);
   begin
      if Next.Kind /= T_WORD then
         Syntax_Error (Next, "expect word token");
      end if;
      return Next;
   end Read_Word_Token;

   ----------------
   -- Skip_Token --
   ----------------

   procedure Skip_Token (B : in out Token_Buffer) is
      T : Token := Read_Token (B);
      pragma Unreferenced (T);
   begin
      null;
   end Skip_Token;

   ----------------
   -- Unget_Char --
   ----------------

   procedure Unget_Char (B : in out Token_Buffer) is
   begin
      Rewind (B.Content);
   end Unget_Char;

end Sh.Tokens.Lexer;
