# CONFIRM_LATER

Where you can land guesses which aren't pivotal for later confirmation or adjustment.

## Answers in the environment

* A shield's name in `{{SHIELD}}` has everything but letters and digits as `_`, so `no-edit-git` stands as `no_edit_git_1`.
* An answer too long for the environment is not caught: the call fails to start and reads as any failed tool.
* `m8 @` and `m8 send` drop every `M8_EXCLAMATION_*` they inherit, for the provider as well as for tools.
