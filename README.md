# schematic.vim

Schematic adds lightweight project definition and task support to vim and neovim. A Schematic project is a JSON file
describing targets (outputs with associated clean, build and run scripts) and configurations (containers for
properties). For example:

    {
      "targets":
      {
        "Program": { "build": "make my-program", "clean": "make clean", "run": "my-program" },
        "Tests": { "build": "make unit-tests", "clean": "make clean", "run": "cd tests\nrun-tests" },
      },

      "configurations":
      {
        "Debug": { "directory": "build/debug" },
        "Release": { "directory": "build/release" }
      }
    }

`:SUpdate` triggers Schematic, causing it to search the current directory (and upwards) for a `schematic.json` file
defining a project like the above. If found, Schematic will load the project data and set the current configuration and
target to the first configuration and target found in the file.

`:SConfig <configuration>` and `:STarget <target>` set the current configuration and target, respectively.

`:SClean`, `:SBuild` and `:SRun` invoke the clean, build and run scripts for the current target using the current
configuration.

For more detailed documentation, check out `:help schematic`.


## Installation

Schematic has no special installation requirements. Use your preferred plugin management method to install it.

