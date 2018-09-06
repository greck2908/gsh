------------------------------------------------------------------------------
--                                                                          --
--                                  G S H                                   --
--                                                                          --
--                       Posix_Shell.Builtins.Uname                         --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                                                                          --
--                       Copyright (C) 2010-2014, AdaCore                   --
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

package Posix_Shell.Builtins.Uname is

   function Uname_Builtin
     (S : in out Shell_State; Args : String_List) return Integer;
   --  Implement the "uname" builtin.
   --  Deviation from Standard (to match Cygwin behaviour):
   --    * added options:
   --          -o (op system),
   --          -p (processor),
   --          -i (hardware platform)
   --    * -a option is equivalent to -mnrsvo (instead of -mnrsv)

end Posix_Shell.Builtins.Uname;