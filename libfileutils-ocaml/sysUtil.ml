(** A module to provide the core system utilities to 
manipulate file and directory. All function nearly match
common unix utilities ( but try to be more portable )*)

open SysPath;;

type filename = string

type interactive =
	  Force
	| Ask of (filename -> bool)

type fs_type = 
	Dir  
	| File 
	| Dev_char
	| Dev_block
	| Link
	| Fifo
	| Socket
;;	

type test_file =
	Is_dev_block
	| Is_dev_char
	| Is_dir
	| Exists
	| Is_file
	| Is_set_group_ID
	| Has_sticky_bit
	| Is_link
	| Is_pipe
	| Is_readable
	| Is_writeable
	| Size_not_null
	| Is_socket
	| Has_set_user_ID
	| Is_exec
	| Is_owned_by_user_ID
	| Is_owned_by_group_ID
	| Is_newer_than of string * string
	| Is_older_than of string * string
	| Has_same_device_and_inode of string * string
	| And of test_file * test_file
	| Or of test_file * test_file
	| Not of test_file
	| Match of string
	| True
	| False
;;

exception File_doesnt_exist ;;
exception RmDirNotEmpty;;
exception MkdirMissingComponentPath;;
exception MkdirDirnameAlreadyUsed;;
exception CpCannotCopyDirToDir;;
exception CpCannotCopyDirToFile;;
exception CpCannotCopy;;
exception CpNoSourceFile;;
exception MvNoSourceFile;;

let stat_type filename =
	try
		let stats = Unix.stat filename
		in
		match stats.Unix.st_kind with
		 Unix.S_REG -> File 
		| Unix.S_DIR -> Dir 
		| Unix.S_CHR -> Dev_char 
		| Unix.S_BLK -> Dev_block
		| Unix.S_LNK -> Link
		| Unix.S_FIFO -> Fifo 
		| Unix.S_SOCK -> Socket
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist 
;;

let stat_type_match tp filename = stat_type filename = tp
;;

let stat_right filename =
	try
		let stats = Unix.stat filename
		in
		stats.Unix.st_perm 
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist
;;

let stat_right_match right filename = 
	(stat_right filename land right) <> 0
;;

let right_sticky       = 0o1000
;;

let right_sticky_group = 0o2000
;;

let right_sticky_user  = 0o4000
;;

let right_exec         = 0o0111
;;

let right_write        = 0o0222
;;

let right_read         = 0o0444
;;

let stat_size filename =
	try
		let stats = Unix.stat filename
		in
		stats.Unix.st_size
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist
;;

let stat_ugid filename =
	try
		let stats = Unix.stat filename
		in
		(stats.Unix.st_uid,stats.Unix.st_gid)
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist
;;

let stat_mtime filename =
	try
		let stats = Unix.stat filename
		in
		stats.Unix.st_mtime
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist
;;

let stat_dev filename =
	try
		let stats = Unix.stat filename
		in
		(stats.Unix.st_dev,stats.Unix.st_rdev)
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist
;;

let stat_inode filename =
	try
		let stats = Unix.stat filename
		in
		stats.Unix.st_ino
	with Unix.Unix_error(_) ->
		raise File_doesnt_exist
;;

let rec compile_filter flt =
	let res_filter =
		match flt with
		  Is_dev_block    -> stat_type_match Dev_block
		| Is_dev_char     -> stat_type_match Dev_char
		| Is_dir          -> stat_type_match Dir
		| Is_file         -> stat_type_match File
		| Is_set_group_ID -> stat_right_match right_sticky_group
		| Has_sticky_bit  -> stat_right_match right_sticky
		| Is_link         -> stat_type_match Link
		| Is_pipe         -> stat_type_match Fifo
		| Is_readable     -> stat_right_match right_read
		| Is_writeable    -> stat_right_match right_write
		| Size_not_null   -> fun x -> (stat_size x) > 0
		| Is_socket       -> stat_type_match Socket
		| Has_set_user_ID -> stat_right_match right_sticky_user
		| Is_exec         -> stat_right_match right_exec
		| True            -> fun x -> true
		| False           -> fun x -> false
		| Is_owned_by_user_ID  -> fun x -> Unix.geteuid () = fst (stat_ugid x)
		| Is_owned_by_group_ID -> fun x -> Unix.getegid () = snd (stat_ugid x)
		| Is_newer_than(f1,f2) -> fun x -> (stat_mtime f1) < (stat_mtime f2)
		| Is_older_than(f1,f2) -> fun x -> (stat_mtime f1) > (stat_mtime f2)
		| Has_same_device_and_inode(f1,f2) -> 
			fun x -> (stat_dev f1,stat_inode f1) = (stat_dev f2, stat_inode f2)
		| Exists	  -> fun x -> let _ = stat_right x in  true
		| And(flt1,flt2) ->
			begin
			fun x -> 
				let cflt1 = (compile_filter flt1)
				in
				let cflt2 = (compile_filter flt2)
				in
				(cflt1 x) && (cflt2 x)
			end
		| Or(flt1,flt2) ->
			begin
			fun x -> 
				let cflt1 = (compile_filter flt1)
				in
				let cflt2 = (compile_filter flt2)
				in
				(cflt1 x) || (cflt2 x)
			end
		| Not(flt1) ->
			begin
			fun x -> 
				let cflt1 = (compile_filter flt1)
				in
				not (cflt1 x)
			end	
		| Match(r) ->
			begin
			let reg = Str.regexp r
			in
			fun x -> Str.string_match reg x 0
			end
	in
	fun x -> ( try res_filter x with File_doesnt_exist -> false )
;;

let list_dir dirname =
	let hdir = Unix.opendir dirname
	in
	let rec list_dir_aux lst =
		try
			let filename = Unix.readdir hdir
			in
			let complete_path = 
				concat dirname filename
			in
			list_dir_aux (complete_path :: lst)
		with End_of_file ->
			Unix.closedir hdir;
			lst
	in
	list_dir_aux []
;;	


let filter flt lst =
	let cflt = compile_filter flt
	in
	List.filter cflt lst
;;

let test tst fln =
	let ctst = compile_filter tst
	in
	ctst fln 
;;	

let which ?(path) fln =
	let real_path =
		match path with
		  None ->
			explode_path (Sys.getenv "PATH")
		| Some x ->
			x
	in
	let ctst x = 
		test (And(Is_exec,Not(Is_dir))) (concat x fln)
	in
	let which_path =
		List.find ctst real_path
	in
	concat which_path fln
;;

let mkdir ?(parent=false) ?mode fln =
	let real_mode = 
		match mode with
		  Some x -> x
		| None -> 0o0755
	in
	let mkdir_simple fln =
		if test Exists fln then
			if test Is_dir fln then
				()
			else
				raise MkdirDirnameAlreadyUsed 
		else
			try 
				Unix.mkdir fln real_mode 
			with Unix.Unix_error(Unix.ENOENT,_,_) | Unix.Unix_error(Unix.ENOTDIR,_,_) ->
				raise MkdirMissingComponentPath
	in
	if parent then
		let exploded_path = explode fln
		in
		let _ = List.fold_left (fun x y -> 
			match x with 
			  Some s -> let next = concat s y in
			  	mkdir_simple next; Some next
			| None ->
				mkdir_simple y; Some y
			) None exploded_path
		in
		()
	else
		mkdir_simple fln
;;		

let touch ?(create=true) fln =
	if (test (And(Exists,Is_file)) fln) || create then
		close_out (open_out fln)
	else 
		()
;;

let find tst fln =
	let ctest = compile_filter (And(tst,Not(Or(Match(".*/\\.\\.$"),Match(".*/\\.$")))))
	in
	let cdir  = compile_filter (And(Is_dir,Not(Or(Match(".*/\\.\\.$"),Match(".*/\\.$")))))
	in
	let rec find_simple fln =
		let dir_content = 
			list_dir fln
		in
		List.fold_left 
			(fun x y -> List.rev_append (find_simple y) x)
			(List.filter ctest dir_content)
			(List.filter cdir dir_content)
	in
	if test Is_dir fln then
		find_simple fln
	else if ctest fln then
		[fln]
	else
		[]
;;

let rm ?(force=Force) ?(recurse=false) fln =
	let rm_simple fln =
		let doit = 
			match force with
		 	  Force -> true
			| Ask ask -> ask fln
		in
		if doit && (test Is_dir fln) then
			try 
				Unix.rmdir fln
			with Unix.Unix_error(Unix.ENOTEMPTY,_,_) ->
				raise RmDirNotEmpty
		else if doit then
			Unix.unlink fln
		else 
			()
	in
	if recurse then
		begin
		List.iter rm_simple (find True fln);
		rm_simple fln
		end
	else
		rm_simple fln
;;


let cp ?(force=Force) ?(recurse=false) fln_src fln_dst = 
	let cwd = Sys.getcwd ()
	in
	let cp_simple fln_src fln_dst =
		let doit = 
			(* We do not accept to copy a file over himself *)
			(* Use reduce to get rid of trick like ./a to a *)
			(
				( reduce fln_src ) <> ( reduce fln_dst )
			)
			&&
			(
				if test Exists fln_dst then
					match force with
					  Force -> true
					| Ask ask -> ask fln_dst
				else
					true
			)
		in
		if doit then
			match stat_type fln_src with
			  File -> 
				begin
					let buffer_len = 1024
					in
					let buffer = String.make buffer_len ' '
					in
					let read_len = ref 0
					in
					let ch_in = open_in_bin fln_src
					in
					let ch_out = open_out_bin fln_dst
					in
					while (read_len := input ch_in buffer 0 buffer_len; !read_len <> 0 ) do
						output ch_out buffer 0 !read_len
					done;
					close_in ch_in;
					close_out ch_out
				end
			| Dir ->
				mkdir fln_dst
			(* We do not accept to copy this kind of files *)
			(* It is too POSIX specific, should not be     *)
			(* implemented on other platform               *)
			| Link 
			| Fifo 
			| Dev_char 
			| Dev_block
			| Socket ->
				raise CpCannotCopy
		else
			()
	in
	let cp_dir () = 
		let fln_src_abs = make_absolute cwd fln_src
		in
		let fln_dst_abs = make_absolute cwd fln_dst
		in
		let fln_src_lst = find True fln_src_abs
		in
		let fln_dst_lst = List.map 
			(fun x -> make_absolute fln_dst_abs (make_relative fln_src_abs x))
			fln_src_lst
		in
		List.iter2 cp_simple fln_src_lst fln_dst_lst
	in
	match (test Is_dir fln_src, test Is_dir fln_dst, recurse) with
	  ( true, true, true) ->
	  	cp_dir ()
	| ( true, true,false) ->
		raise CpCannotCopyDirToDir
	| ( true,false, true) ->
		if test Exists fln_dst then
			raise CpCannotCopyDirToFile
		else
			(mkdir fln_dst; cp_dir ())
	| ( true,false,false) ->
		raise CpCannotCopyDirToDir
	| (false, true, true) 
	| (false, true,false) ->
		if test Exists fln_src then
			let fln_src_abs = make_absolute cwd fln_src
			in
			let fln_dst_abs = make_absolute cwd fln_dst
			in
			cp_simple fln_src_abs (make_absolute fln_dst_abs (basename fln_src_abs))
	| (false,false, true) 
	| (false,false,false) ->
		if (test Exists fln_src) then
			cp_simple (make_absolute cwd fln_src) (make_absolute cwd fln_dst)
		else 
			raise CpNoSourceFile
;;

let rec mv ?(force=Force) fln_src fln_dst =
	let cwd = Sys.getcwd ()
	in
	let fln_src_abs =  make_absolute cwd fln_src 
	in
	let fln_dst_abs =  make_absolute cwd fln_dst
	in
	if fln_src_abs <> fln_dst_abs then
	begin
		if test Exists fln_dst_abs then
		begin
			let doit = 
				match force with
				  Force -> true
				| Ask ask -> ask fln_dst
			in
			if doit then
			begin
				rm fln_dst_abs;
				mv fln_src_abs fln_dst_abs
			end
			else
				()
		end
		else if test Is_dir fln_dst_abs then
			mv ~force:force fln_src_abs (make_absolute fln_dst_abs (basename fln_src_abs))
		else if test Exists fln_src_abs then
			Unix.rename fln_src_abs fln_src_abs
		else
			raise MvNoSourceFile
	end
	else
		()
;;
