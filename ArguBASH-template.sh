#!/bin/bash

# NOTE:  This is a template script with declarative argument parsing
#
#################################################################
# ARGUMENT DEFINITION
#
# This script template shows a number of command line options that
# are handled via the declarative argument parser for bash scripts.
#
# When processing command line arguments:
# - Internal variable names use underscores: vm_sku
# - Command line options use dashes:         --vm-sku
# This conversion happens automatically in the argument parser
#
# The long --help output uses the comments above the default values
# below to provide the long help text.  However, only comments that
# start with '# ' (that is hash and space) are used.  This allows us
# to also have comments that are just for the script maintainer
# such as those starting with '##'
#
# Set EXTRA_ARGS=true if you want to collect positional arguments
# into the "extra_args" array.  This includes support for
# passing the remainder of the command line via "--"
# If not set to true, then the script will only accept
# the arguments that are defined in the ARGS_AND_DEFAULTS
EXTRA_ARGS=false
# This is a list of arguments that are not
# tied to an option.  Useful if you want positionals.
extra_args=()
ARGS_AND_DEFAULTS=(
   ## Some Example arguments
   # The directory to operate on, defaults to current directory
   dir="$(pwd)"

   # The ssh public key file to use
   # This is your public key (.pub file) for VM access
   # See README.md and STEP-BY-STEP.md for details
   ssh_public_key=${HOME}/.ssh/id_rsa.pub

   # The OS image to use for the VM
   # "AUTO": Find latest Ubuntu HPC image (for GPUs)
   # "22.04": Use official Ubuntu 22.04 LTS image
   # "24.04": Use official Ubuntu 24.04 LTS image
   # Or enter a full image URN for specific requirements
   # Note that 22.04 can be enabled for FIPS mode
   os_image=24.04

   # The VM size/SKU determining CPU/memory/etc.
   # Standard_D32s_v3: 32 vCPUs, 128 GB RAM (default)
   # Standard_D16s_v3: 16 vCPUs, 64 GB RAM (smaller)
   # GPU VMs (NC* series) require quota approval
   vm_sku=Standard_D32s_v3

   # Size of the VM OS disk in gigabytes
   # 512GB is recommended for most development work
   # Increase only if you really need more space
   disk_size_gb=512

   # Controls post-creation VM setup and configuration
   # When true, installs dev tools, Docker, Azure CLI,
   # Git credential manager, and sets up blobfuse mounts
   # Set to false only if you'll handle setup manually
   configure_vm=true

   # The verbosity level of script output
   # 0 = minimal output (quiet)
   # 1 = standard logging (recommended)
   # 2 = detailed debugging output
   verbosity=1

   # Run in simulation mode without making actual changes
   # Set to "true" to see what would happen without
   # creating any resources. Useful for testing or
   # reviewing changes.
   # Keep as "false" for normal operation
   dry_run=false
)
# END of ARGUMENT DEFINITION
##################################################################

##################################################################
# ARGUMENT PARSER
#
# Data driven argument parser - Using bash trickery...
# This "if" is here just so we can fold it away in many editors
if true; then
   # Note that this argument parser is designed to be used in a script
   # directly such that the script is fully self-contained.
   # Also, by using the structure seen in this file, the ArguBASH-completion
   # definition can be sourced into your bash environment to provide tab
   # completion for the arguments defined by this parser.

   function _error() {
      echo >&2 ERROR: "$@"
   }

   # We compute max arg length here while checking for defaults.
   # We start at 4 as "help" is 4 characters and we always support help.
   ARGS_AND_DEFAULTS_MAX_LEN=4

   # Set all of the defaults but only if the variable is not already set
   # This way a user can override the defaults by setting them in their environment
   for default in "${ARGS_AND_DEFAULTS[@]}"; do
      key=${default%=*}
      # Validate that the key is a valid variable name - if not, error with details
      if [[ ! $key =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
         _error "Parameter '$key' should start with a letter and only contain letters, numbers, and underscores"
         exit 1
      fi
      [[ ${#key} -le ${ARGS_AND_DEFAULTS_MAX_LEN} ]] || ARGS_AND_DEFAULTS_MAX_LEN=${#key}
      [[ -n ${!key} ]] || declare ${key}="${default#*=}"
   done

   function show_help() {
      # If we want long help (--help), parse out the help text from
      # the script comments for each of the defaults.  A fun way to
      # get the comments to also be the detailed help text.  Thus they
      # are declarative and directly related to the code.
      local arg_indent="    "
      ARGS_AND_DEFAULTS_MAX_LEN=$(( ARGS_AND_DEFAULTS_MAX_LEN + 2 ))
      if [[ ${1} == --help ]] && [[ -f ${BASH_SOURCE} ]]; then
         local help_text=""
         local left_blank=$(printf "${arg_indent}%-*s" ${ARGS_AND_DEFAULTS_MAX_LEN} "")
         local in_help=0
         while read -r line; do
            if [[ ${line} == "ARGS_AND_DEFAULTS=("* ]]; then
               in_help=1
            elif [[ ${line} == ")" ]]; then
               break
            elif [[ ${in_help} -eq 1 ]]; then
               # Trim leading whitespace
               line="${line#"${line%%[![:space:]]*}"}"
               if [[ ${line} == "# "* ]]; then
                  # The comments are the extended help text
                  help_text+="${left_blank} ${line###}\n"
               elif [[ ${line} == *"="* ]]; then
                  argument="${line%=*}"
                  # If the script's default is different show it:
                  [[ ${!argument} == ${line#*=} ]] || help_text="${left_blank}  original: ${line#*=}\n${help_text}"
                  declare "_help_${argument}"="${help_text}${left_blank} ------------------------------------------------------"
                  help_text=""
               fi
            fi
         done < "${BASH_SOURCE}"
      fi

      if [[ ${EXTRA_ARGS} == true ]]; then
         echo "Usage: ${BASH_SOURCE} [--<override> value] [--help|-h] <positional args>"
      else
         echo "Usage: ${BASH_SOURCE} [--<override> value] [--help|-h]"
      fi
      {
         for var in "${ARGS_AND_DEFAULTS[@]}"; do
            key=${var%=*}
            printf "${arg_indent}--%-*s" ${ARGS_AND_DEFAULTS_MAX_LEN} "${key//_/-}"
            echo "default: ${!key}"
            long_help="_help_${key}"
            [[ ! -n ${!long_help} ]] || echo -e "${!long_help}"
         done
         if [[ ${EXTRA_ARGS} == true ]]; then
            printf "${arg_indent}--%-*s" ${ARGS_AND_DEFAULTS_MAX_LEN} ""
            echo "pass remaining arguments"
         fi
         if [[ -n ${!long_help} ]]; then
            printf "${arg_indent}-%-*s " ${ARGS_AND_DEFAULTS_MAX_LEN} "h"
            echo "for quick argument summary"
         else
            printf "${arg_indent}--%-*s" ${ARGS_AND_DEFAULTS_MAX_LEN} "help"
            echo "for more complete help"
         fi
      }
   }

   # Now, process the command line arguments - This way we can override the
   # default values via command line arguments
   while [[ $# -gt 0 ]]; do
      arg="${1}"
      shift 1
      # Help is a special case
      if [[ ${arg} == --help || ${arg} == -h ]]; then
         show_help ${arg}
         exit 0
      fi
      if [[ ${arg} == -- ]] && [[ ${EXTRA_ARGS} == true ]]; then
         # This is a special case for when you want to pass
         # the remaining arguments to the extra_args array
         extra_args+=("${@}")
         break
      elif [[ ${arg} == --* ]] || [[ ! ${EXTRA_ARGS} == true ]]; then
         valid=false
         for var in "${ARGS_AND_DEFAULTS[@]}"; do
            key=${var%=*}
            if [[ ${arg} == --${key//_/-} ]]; then
               # if there is no additional argument or it looks like a flag
               # then it is invalid - this does mean you can't have a value
               # that starts with a dash "-" but for what we use, that is fine.
               # This catches typos or mistakes in the command line options.
               if [[ $# -lt 1 || ${1} == -* ]]; then
                  _error "Argument '${arg}' requires a value"
                  exit 1
               fi
               valid=true
               declare ${key}="${1}"
               shift 1
               break
            fi
         done
         if [[ ${valid} == false ]]; then
            _error "Unknown argument: '${arg}'"
            show_help -h >&2
            exit 1
         fi
      else
         # Most likely a positional argument
         extra_args+=("${arg}")
      fi
   done

   # Unset any that are blank (trick used later)
   for var in "${ARGS_AND_DEFAULTS[@]}"; do
      key=${var%=*}
      [[ -n ${!key} ]] || unset ${key}
   done

   # Log the effective command line options we are running with
   # such that it would be easy to reproduce even if you had set some
   # of the values in your environment or via the command line.
   # The trick to get the command line arguments to be printed with whatever
   # escaping needed to get them to turn out correctly for the shell is to
   # let the shell log it for us and we just clean it up.
   readonly RUNNING_WITH_OPTIONS=$(
      declare -a effective_cmd_args=("${BASH_SOURCE}")
      for var in "${ARGS_AND_DEFAULTS[@]}"; do
         key=${var%=*}
         effective_cmd_args+=("--${key//_/-}" "${!key}")
      done
      [[ ${#extra_args} -lt 1 ]] || effective_cmd_args+=("--" "${extra_args[@]}")
      effective_cmd_line=$( (set -x; : "${effective_cmd_args[@]}") 2>&1 )
      echo "${effective_cmd_line/*+ : }"
   )
   [[ ${verbosity-0} -lt 2 ]] || echo >&2 -e "\nRunning with these effective options:\n\n${RUNNING_WITH_OPTIONS}\n"
fi
# END of ARGUMENT PARSER
##################################################################

## Your code starts here...

_error "This is just a template script - actual work would go here..."
exit 99
