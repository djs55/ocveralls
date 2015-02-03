(*
    Ocveralls - Generate JSON file for http://coveralls.io API
                from Bisect (http://bisect.x9c.fr) data.

    Copyright (C) 2015 Julien Sagot

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)

(* FIXME: Running this tool will generate a bisectX.out file
 * in current directory. because of the [at_exit] call in Bisect.Runtime. *)

module B = Bisect.Common

(** [source_and_coverage cov "foo.ml"] returns
    the list of lines read in "foo.ml" and the list of coverage
    metadata for each line ("0", "null", "1", ...) *)
let source_and_coverage
    : int array -> string -> string list  * int list
  = fun cov src ->
  let len = Array.length cov in
  let points =
    List.map ( fun p -> ( p.B.offset,
			  if p.B.identifier < len
			  then cov.(p.B.identifier)
			  else 0 ) )
	     (B.read_points src) in

  let chan = open_in src in

  (* For a line and some points:
   * - Split points in two groups:
   *   points contained in the line, and the rest.
   * - Determine if every contained points has been visited and
   *   attribute a coverage metadata ("0", "null", ...) to the line.
   * - Restart with next line and reamining points. *)
  let rec process points (src, cov) = match input_line chan with
    | line_src ->
       let end_off = pos_in chan in
       let (current, remaining) =
	 List.partition (fun (o, _) -> o < end_off) points in
       let (min_visits, visited, unvisited) =
         List.fold_left
           (fun (m, v, u) nb -> (min m nb, v || nb > 0, u || nb = 0))
           (max_int, false, false)
           (List.map snd current) in
       let line_cov = if unvisited then 0
		      else if visited then min_visits
		      else -1 in
       process remaining (line_src :: src, line_cov :: cov)
    | exception End_of_file -> close_in chan ;
			       (List.rev src, List.rev cov)
		in process points ([], [])

(* FIXME:
 * Assumes that all files contains data about
 * the same set of files.
 * If the first runtime data file misses a source file,
 * final data will also miss it.  *)
let coverage_data
    : string list -> (string * int array) list
  = fun files ->
  if files = [] then []
  else
    (* Combine all files runtime data:
     * point coverage is the sum of counters of
     * each file associated to it. *)
    let combine a1 a2 = Array.mapi (fun i v -> v + a2.(i)) a1 in
    let data = List.map B.read_runtime_data files in
    let hd = List.hd data in
    let tl = List.tl data in
    List.map (fun (k, v) ->
	      (k, try List.map (List.assoc k) tl
		      |> List.fold_left combine v
		  with Not_found -> [||])) hd
