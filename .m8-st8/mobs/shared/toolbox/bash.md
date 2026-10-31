
* :toolbox::bash
* :toolbox::bash
  > > Run a bash command.
  > > Use $TMPDIR instead of /tmp.
  >
  > :shield:workbench
  > :shield:secure airgap
  > ```bash
  > set -m
  > bash -euo pipefail -c "$__command__" > \
  >  >(awk 'BEGIN{n=24000}{l=length+1;if(n>0){print substr($0,1,n);fflush()}n-=l}END{if(n<0)print "[truncated at 24KB]"}') \
  >  & p=$!
  > (sleep "${__timeout__:-30}"; kill -TERM -"$p" 2>/dev/null) & t=$!
  > s=0; wait "$p" 2>/dev/null || s=$?; kill -TERM -"$t" 2>/dev/null || :; wait "$t" 2>/dev/null || :; exit "$s"
  > ```
  > * command string
  >   The bash command to run.
  > * timeout? number
  >   Seconds before stopping the command (default 30).

