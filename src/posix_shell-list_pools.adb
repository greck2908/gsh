with Posix_Shell.Traces; use Posix_Shell.Traces;

package body Posix_Shell.List_Pools is

   function New_Element
     (Pool : in out List_Pool;
      Item : Token)
      return Token_List;

   procedure Append
     (Pool : in out List_Pool; Source : in out Token_List; Item : Token)
   is
      L : constant Token_List := New_Element (Pool, Item);
   begin
      pragma Debug (Log ("append", Image (Item)));
      if Source = Null_List then
         Source := L;
         Pool.Table (Source).Last := Source;
      else
         Pool.Table (Pool.Table (Source).Last).Next := L;
         Pool.Table (Source).Last := L;
      end if;
   end Append;

   procedure Append
     (Pool : in out List_Pool; Source : in out Token_List; Item : Token_List)
   is
   begin
      if Source = Null_List then
         Source := Item;
      elsif Item /= Null_List then
         Pool.Table (Pool.Table (Source).Last).Next := Item;
         Pool.Table (Source).Last := Pool.Table (Item).Last;
      end if;
   end Append;

   function Prepend
     (Pool : in out List_Pool; Source : Token_List; Item : Token)
     return Token_List
   is
      L : constant Token_List := New_Element (Pool, Item);

   begin
      pragma Debug (Log ("prepend", Image (Item)));
      if Source /= Null_List then
         Pool.Table (L).Next := Source;
         Pool.Table (L).Last := Pool.Table (Source).Last;
      else
         Pool.Table (L).Last := L;
      end if;
      return L;
   end Prepend;

   procedure Deallocate (Pool : in out List_Pool; Source : Token_List) is
      Next_Free : constant Token_List := Pool.Table (1).Next;
   begin
      Pool.Table (1).Next := Source;
      Pool.Table (Pool.Table (Source).Last).Next := Next_Free;
   end Deallocate;

   function Get_Element (Pool : List_Pool; Source : Token_List) return Token
   is
   begin
      return Pool.Table (Source).T;
   end Get_Element;

   function Is_Empty (Pool : List_Pool; Source : Token_List) return Boolean
   is
   begin
      return Source = 0;
   end Is_Empty;

   function New_Element
     (Pool : in out List_Pool;
      Item : Token)
      return Token_List
   is
   begin
      pragma Debug (Log ("new_element", Image (Item)));
      if Pool.Table (1).Next = Null_List then
         Append (Pool, (Item, 0, 0));
         return Last (Pool);
      else
         declare
            Result : constant Token_List := Pool.Table (1).Next;
         begin
            Pool.Table (1).Next := Pool.Table (Result).Next;
            Pool.Table (Result) := (Item, 0, 0);
            return Result;
         end;
      end if;
   end New_Element;

   function Next (Pool : List_Pool; Source : Token_List) return Token_List is
   begin
      return Pool.Table (Source).Next;
   end Next;

   function New_Pool return List_Pool is
      Result : List_Pool;
   begin
      Init (Result);
      Append (Result, (Null_Token, 0, 0));
      return Result;
   end New_Pool;
end Posix_Shell.List_Pools;