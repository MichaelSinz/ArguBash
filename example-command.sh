#!/bin/bash

#################################################################
# ARGUMENT DEFINITION
#
EXTRA_ARGS=true
extra_args=()
ARGS_AND_DEFAULTS=(
   # The directory to operate on, defaults to current directory
   dir="$(pwd)"

   # Verbosity level (0=quiet, 1=normal, 2=verbose)
   # Controls how much information is displayed during execution
   verbosity=1

   # Run in simulation mode without making changes
   # Set to true to see what would happen without actual execution
   dry_run=false

   # Maximum number of parallel operations
   # Higher values may improve performance but use more resources
   parallel=4
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
      key=${default/=*}
      # Validate that the key is a valid variable name - if not, error with details
      if [[ ! $key =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
         _error "Parameter '$key' should start with a letter and only contain letters, numbers, and underscores"
         exit 1
      fi
      [[ ${#key} -le ${ARGS_AND_DEFAULTS_MAX_LEN} ]] || ARGS_AND_DEFAULTS_MAX_LEN=${#key}
      [[ -n ${!key} ]] || declare ${default}
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
                  argument="${line/=*}"
                  # If the script's default is different show it:
                  [[ ${!argument} == ${line/*=} ]] || help_text="${left_blank}  original: ${line/*=}\n${help_text}"
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
            key=${var/=*}
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
            key=${var/=*}
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
      key=${var/=*}
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
         key=${var/=*}
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

# This is just a no-op example command to demonstrate ArguBASH
[[ ${verbosity} -gt 1 ]] && set -x
echo "This is a no-op example command that just shows the arguments:"
echo "  Directory: ${dir}"
echo "  Verbosity: ${verbosity}"
echo "  Dry run: ${dry_run}"
echo "  Parallel: ${parallel}"
if [[ ${#extra_args[@]} -gt 0 ]]; then
   echo "  Extra args:"
   for xtra in "${extra_args[@]}"; do
      echo "      | ${xtra}"
   done
fi
# Exit without doing anything
exit 0
