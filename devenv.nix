{ pkgs, config, ... }:

{
  # SWI-Prolog (current stable), a C compiler with OpenMP, and make.
  packages = [
    pkgs.swi-prolog
    pkgs.gcc
    pkgs.gnumake
  ];

  # Keep SWI-Prolog packs inside the project, not ~/.local/share/swi-prolog.
  env.SWIPL_PACK_PATH = "${config.devenv.state}/swipl-packs";

  # Link this project into the pack directory so that
  # use_module(library(pppc)) and `swipl pppc ...` work anywhere in the shell.
  enterShell = ''
    mkdir -p "$SWIPL_PACK_PATH"
    if [ ! -e "$SWIPL_PACK_PATH/pppc" ]; then
      swipl pack install -y .
    fi
  '';

  enterTest = ''
    make test
  '';
}
