
let s:schematic_jobs = {}

function s:EchoError(message)
  echohl Error
  echomsg a:message
  echohl None
endfunction

function s:CompleteFromDictionary(dictionary, argument)
  let result = []
  for key in keys(a:dictionary)
    if len(a:argument) == 0 || "^" . key =~ a:argument
      call add(result, key)
    endif
  endfor
  call sort(result)
  return result
endfunction

function schematic#CompleteConfigurationName(argument, command_line, cursor_position)
  return s:CompleteFromDictionary(t:schematic_configurations, a:argument)
endfunction

function schematic#CompleteTargetName(argument, command_line, cursor_position)
  return s:CompleteFromDictionary(t:schematic_targets, a:argument)
endfunction

function s:RaiseSchematicUpdatedEvent()
  " vim will produce an error if we trigger the autocommand while it's not defined by the user.
  if exists("#User#SchematicUpdated")
    doautoall <nomodeline> User SchematicUpdated
  endif
endfunction

function schematic#SetConfiguration(config)
  if !has_key(t:schematic_configurations, a:config)
    call s:EchoError("Schematic: '" . a:config . "' is not a configuration.")
  endif

  let t:schematic_current_configuration = a:config
  call s:RaiseSchematicUpdatedEvent()
endfunction

function schematic#SetTarget(target)
  if !has_key(t:schematic_targets, a:target)
    call s:EchoError("Schematic: "" . a:target . "" is not a target.")
  endif

  let t:schematic_current_target = a:target
  call s:RaiseSchematicUpdatedEvent()
endfunction

function s:FinalizeJob(job_key, status) abort
  let job = s:schematic_jobs[a:job_key]
  if a:status != 0
    execute "caddfile " . fnameescape(job.output_file)
    execute "copen"
  endif

  let target = job["target"]
  let t:schematic_targets[target]["running"] = 0

  call delete(job.script_file)
  call delete(job.output_file)
  call remove(s:schematic_jobs, a:job_key)

  execute "redrawstatus"
endfunction

function s:OnJobOutputNeovim(job_id, data, event) abort
  let job = s:schematic_jobs[a:job_id]
  let output_file = job["output_file"]
  call writefile(a:data, output_file, "ab")
endfunction

function s:OnJobCompleteNeovim(job_id, status, event) abort
  let job = s:schematic_jobs[a:job_id]
  let t:schematic_targets[job["target"]]["status"] = a:status
  call s:FinalizeJob(a:job_id, a:status)
endfunction

function s:OnJobOutputVim(channel, data) abort
  let channel_info = ch_info(a:channel)
  let job = s:schematic_jobs[channel_info["id"]]
  let output_file = job["output_file"]
  call writefile(split(a:data, "\n", 1), output_file, "ab")
endfunction

function s:OnJobCompleteVim(channel) abort
  let channel_info = ch_info(a:channel)
  let job = s:schematic_jobs[channel_info["id"]]
  let job_info = job_info(job["object"])

  let status = job_info["exitval"]
  let t:schematic_targets[job["target"]]["status"] = status
  call s:FinalizeJob(channel_info["id"], status)
endfunction

function schematic#Perform(action) abort
  let target = t:schematic_targets[t:schematic_current_target]
  if target["running"] != 0
    call s:EchoError("Schematic: "" . t:schematic_current_target . "" is already running.")
    return
  endif

  let script_file = tempname()
  call writefile(target[a:action], script_file)
  call setfperm(script_file, "rwxr--r--")

  let configuration = t:schematic_configurations[t:schematic_current_configuration]
  let working_directory = configuration["directory"]
  let options = {"cwd": working_directory}
  if has("nvim")
    let options.on_stdout = function("s:OnJobOutputNeovim")
    let options.on_stderr = function("s:OnJobOutputNeovim")
    let options.on_exit = function("s:OnJobCompleteNeovim")
    let job_key = jobstart(script_file, options)
    call chanclose(job_key, "stdin")
  else
    let options["callback"] = function("s:OnJobOutputVim")
    let options["close_cb"] = function("s:OnJobCompleteVim")
    let options["mode"] = "raw"
    let job = job_start(script_file, options)
    call ch_close_in(job)

    let job_info = job_info(job)
    let channel_info = ch_info(job_info["channel"])
    let job_key = channel_info["id"]
  endif

  let target["last_action"] = a:action
  let target["running"] = 1
  let s:schematic_jobs[job_key] = {"target":t:schematic_current_target, "script_file":script_file, "output_file":tempname()}
  if !has("nvim")
    " In vim, we must hold a reference to the job object for the duration of the job, or it will get garbage-collected.
    let s:schematic_jobs[job_key]["object"] = job
  endif
endfunction

function s:FindFile(file)
  let current = getcwd()
  while len(current) > 0
    let candidate = current . "/" . a:file
    if filereadable(candidate)
      return candidate
    endif

    let next = fnamemodify(current, ":h")
    if next == current
      break
    endif

    let current = next
  endwhile

  return 0
endfunction

function s:FormatScript(script, target)
  let result = substitute(a:script, "@", a:target, "g")
  return split(result, "\n")
endfunction

function schematic#Update() abort
  let schematic_file_path = s:FindFile(g:schematic_file_name)
  if filereadable(schematic_file_path)
    let t:schematic_name = fnamemodify(schematic_file_path, ":h:t")
    let t:schematic_directory = fnamemodify(schematic_file_path, ":h")
    let t:schematic_current_configuration = ""
    let t:schematic_current_target = ""

    let schematic = json_decode(join(readfile(schematic_file_path), " "))

    let t:schematic_configurations = {}
    let t:schematic_current_configuration = ""
    if has_key(schematic, "configurations")
      for [name, data] in items(schematic["configurations"])
        if len(t:schematic_current_configuration) == 0
          let t:schematic_current_configuration = name
        endif

        let t:schematic_configurations[name] = {"directory": t:schematic_directory . "/" . data["directory"]}
      endfor
    endif

    if len(t:schematic_configurations) == 0
      let t:schematic_configurations[g:schematic_default_configuration_name] = {"name": g:schematic_default_configuration_name, "directory": t:schematic_directory}
      let t:schematic_current_configuration = g:schematic_default_configuration_name
    endif

    let default_clean_script = get(schematic, "default_clean", "")
    let default_build_script = get(schematic, "default_build", "")
    let default_run_script = get(schematic, "default_run", "")

    let t:schematic_targets = {}
    for [name, data] in items(schematic["targets"])
     let target = {"status": 0, "last_action":"", "running":0}
     let target["clean"] = s:FormatScript(get(data, "clean", default_clean_script), name)
     let target["build"] = s:FormatScript(get(data, "build", default_build_script), name)
     let target["run"] = s:FormatScript(get(data, "run", default_run_script), name)

     " The run action depends on the build action.
     call extend(target["run"], target["build"], 0)

     let t:schematic_targets[name] = target
     if len(t:schematic_current_target) == 0
       let t:schematic_current_target = name
     endif
    endfor

    call s:RaiseSchematicUpdatedEvent()
  endif
endfunction 
