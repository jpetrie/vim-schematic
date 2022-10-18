" schematic.vim - project support
" Maintainer: Josh Petrie <http://joshpetrie.net>
" Version:    0.0

if exists("g:loaded_schematic")
  finish
endif

let g:loaded_schematic = 1

if !exists("g:schematic_file_name")
  let g:schematic_file_name = "schematic.json"
endif

if !exists("g:schematic_default_configuration_name")
  let g:schematic_default_configuration_name = "default"
endif

command! SUpdate :call schematic#Update()

command! -nargs=1 -complete=customlist,schematic#CompleteConfigurationName SConfig :call schematic#SetConfiguration(<f-args>)
command! -nargs=1 -complete=customlist,schematic#CompleteTargetName STarget :call schematic#SetTarget(<f-args>)

command! SClean :call schematic#Perform("clean")
command! SBuild :call schematic#Perform("build")
command! SRun :call schematic#Perform("run")

