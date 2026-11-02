
* :toolbox::delegate
  > > Delegate a bounded task with clear objectives, scope, and constraints.
  >
  > ```bash md
  > if [ -n "${__chatID__:-}" ]; then
  >   chatID=$__chatID__
  >   fresh=()
  > else
  >   chatID=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
  >   fresh=(--new)
  > fi
  > m8 say --answer --unwrap "${fresh[@]}" "${__agent__}//delegated-$chatID" "$__task__"
  > printf '\n\n[Use chatID=%s to continue the conversation]\n' "$chatID"
  > ```
  > * task string
  >   The task to complete and any relevant scope or constraints.
  > * chatID? string
  >   The chat ID to resume, if not starting fresh.
* :toolbox::delegate

