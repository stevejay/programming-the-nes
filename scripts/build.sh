#!/bin/zsh

# A simple build script, used to prepare the build directory
# and then invoke the cl65 compile & link utility.

src_file_path=$1
src_file_basename=$src_file_path:t:r
config_file_path=$src_file_path:h/nes.cfg
build_dir_path=$src_file_path:h:h/build
program_file_path=$build_dir_path/program.nes

# If build dir exists then clear it out.
# (The message 'no matches found: ./build/*' can be ignored.)
[ -d $build_dir_path ] && rm $build_dir_path/*

# If build dir does not exist then create it.
[ ! -d $build_dir_path ] && mkdir $build_dir_path

# Invoke the assembler.
ca65 -o $build_dir_path/$src_file_basename.o $src_file_path

# Invoke the linker.
ld65 -C $config_file_path -o $program_file_path $build_dir_path/$src_file_basename.o
