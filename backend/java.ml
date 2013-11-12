module String = Batteries.String
module L = Batteries.List
module Hashtbl = Batteries.Hashtbl
module LL = Batteries.LazyList

open Sexplib
open Std
open Sexp
open PropositionalLogic
open TableauBuchiAutomataGeneration

exception Internal_error of string

open Pretty

let (++) = append
let (>>) x f = f x
let (|>) x f = f x

let make_switch index = function
  | ({name=n},tlabel,_) -> 
    ("case "^(String.lchop n)^":\n" >> text)
    ++(("CD"^(string_of_int index)^"_"^n^ "();  /*" ^ (string_of_logic tlabel) ^ "*/" ^ "\n") >> text)
    ++ ("break;\n" >> text)

let getInterfaceString is s =
  if (L.exists (fun x -> x = s) is) then
    ""
  else
    ("Interface.")

let make_body asignals internal_signals channels o index signals isignals = function
  (* Make the body of the process!! *)
  | ({name=n},tlabel,_) -> 
    let o = (match Hashtbl.find_option o n with Some x -> x | None -> []) in
    let (o,guards) = L.split o in
      (* Now add the transitions *)
    (("/*"^(string_of_logic tlabel)^"*/"^"\n") >> text)
    ++ (("public void CD"^(string_of_int index)^"_"^n^"(){\n") >> text)
    ++ (L.reduce (++) (
        if o <> [] then
    L.map2 (fun x g ->
      (* let updates = ref [] in *)
      let updates = Util.get_updates index g in
      (* let updates1 = List.sort_unique compare (List.map (fun (Update x) ->x) updates) in *)
      let datastmts = (L.filter (fun x -> (match x with | DataUpdate _ ->true | _ -> false)) updates) in
      let updates1 = List.sort_unique compare ((List.map 
                    (fun x -> (match x with | Update x ->x | _ ->  raise (Internal_error "Cannot happen!!"))))
                    (List.filter (fun x -> (match x with | Update _ ->true | _ -> false)) updates)) in
      let to_false = ref signals in
      let () = L.iter (fun x -> to_false := L.filter (fun y -> y <> x) !to_false) updates1 in
      let () = L.iter (fun x -> to_false := L.filter (fun y -> y <> x) !to_false) isignals in
      let g = Util.label "java" !to_false internal_signals channels index updates [] asignals g in
      let updates = updates1 in
      let asignals_names = List.split asignals |> (fun (x,_) -> x) in
      let asignals_options = List.split asignals |> (fun (_,y) -> y) in
      if g <> "false" then
        ("if" >> text)
        ++ ((if g <> "" then ("(" ^ g ^ ") {\n") else "") >> text)
        (* These are the updates to be made here!! *)
        ++ L.fold_left (++) empty (L.mapi (fun i x -> 
          ((if not (L.exists (fun t -> t = x) channels) then 
            ((getInterfaceString internal_signals x)^"CD"^(string_of_int index)^"_"^x) else (getInterfaceString internal_signals x)^x)
          ^ " = true;\nSystem.out.println(\"Emitted: "^x^"\");\n") >> text) updates)
        ++ ((L.fold_left (^) "" (L.map (Util.build_data_stmt asignals index "c") datastmts)) >> text)
        ++ L.fold_left (++) empty (Util.map2i (fun i x y -> 
          (match y with
          | None -> Pretty.empty
          | Some r -> 
              ((getInterfaceString internal_signals x)^"CD"^(string_of_int index)^"_"^x^"_val_pre = "
              ^(getInterfaceString internal_signals x)^"CD" ^ (string_of_int index)^"_"^x^"_val;\n" >> Pretty.text)
              ++ ((getInterfaceString internal_signals x)^"CD"^(string_of_int index)^"_"^x^"_val = "^r.Systemj.v^";\n"  >> Pretty.text)
          ))asignals_names asignals_options)
        ++ L.fold_left (++) empty (L.mapi (fun i x ->
          ((if not (L.exists (fun t -> t = x) channels) then 
            ((getInterfaceString internal_signals x)^"CD"^(string_of_int index)^"_"^x) else (getInterfaceString internal_signals x)^x)
          ^ " = false;\n" >> text)) !to_false)
        ++ (("state = " ^(String.lchop x)^ ";\n") >> text)
        ++ ("return;\n" >> text)
        ++ ("}\n" >> text)
          else empty
    ) o guards
        else [("state =  " ^(String.lchop n)^ "; return;\n">> text)]
      )) 
    ++ ("}\n" >> text)

let make_interface java_channels java_gsigs file_name_without_extension =
  ("package "^file_name_without_extension^";\n" >> text)
  ++ ("public class Interface {\n" >> text)
  ++ java_gsigs
  ++ java_channels
  ++ ("}\n" >> text)


let make_process internal_signals channels o index signals isignals init asignals internal_signals_decl lgn = 
  (("public class CD" ^ (string_of_int index) ^ "{\n") >> text) 
  ++ internal_signals_decl
  ++ (("public int state = " ^(String.lchop init)^"; // This must be from immortal mem\n") >> text)
  ++ ("public void run(){\n" >> text)
  ++ ("switch (state){\n" >> text)
  ++ ((L.reduce (++) (L.map (fun x -> make_switch index (x.node,x.tlabels,x.guards)) lgn)) >> (4 >> indent))
  ++ ("default: System.err.println(\"System went to a wrong state !! \"+state); break;\n" >> text)
  ++ ("}\n}\n" >> text)
  ++ ((L.reduce (++) (L.map (fun x -> make_body asignals internal_signals channels o index signals isignals (x.node,x.tlabels,x.guards)) lgn)) >> (4 >> indent))
  ++ ("}\n" >> text)
  ++ (" " >> line)

let make_main index file_name = 
  (("package "^file_name^";\n") >> text)
  ++ ("public class Main {\n" >> text)
  ++ ("public static void main(String args[]){\n" >> text)
  ++ (L.fold_left (++) empty (L.init index (fun x -> "CD"^(string_of_int x)^" cd"^(string_of_int x)^" = new CD"^(string_of_int x)^"();\n" >> text)))
  ++ ("while(true){\n" >> text) 
  ++ (L.fold_left (++) empty (L.init index (fun x -> "cd"^(string_of_int x)^".run();\n" >> text)))
  ++ ("}\n" >> text) 
  ++ ("}\n" >> text)
  ++ ("}\n" >> text)

let make_java channels internal_signals signals isignals index init asignals internal_signals_decl lgn = 
  let o = Hashtbl.create 1000 in
  let () = L.iter (fun x -> Util.get_outgoings o (x.node,x.guards)) lgn in
  group ((make_process internal_signals channels o index signals isignals init asignals internal_signals_decl lgn) ++ (" " >> line))
    
