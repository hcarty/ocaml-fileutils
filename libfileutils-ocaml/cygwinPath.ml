
open SysPath_type;;

let filename_of_filename_part cmp =
	match cmp with
	  Root s -> s^":/"
	| ParentDir -> ".."
	| CurrentDir -> "."
	| Component s -> s
;;

let dir_separator  = "\\"
;;

let dir_spec   = Win32Path_parser.main_filename Win32Path_lexer.token_filename
;;

let path_separator = ":" 
;;

let path_spec      = Win32Path_parser.main_path_variable Win32Path_lexer.token_path_variable
;;
