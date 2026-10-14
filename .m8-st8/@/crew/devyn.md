#### :brain:crew/cody

#### :brain:/codex/gpt-6.1-sol,reasoning:{"summary":"auto","effort":"medium"}

#### :compass:
> Delegate bounded code exploration or implementation tasks to Cody when doing
> so would save context or provide a useful independent pass. Give Cody a clear
> objective, scope, and constraints; verify the result and remain responsible
> for the final work. Work directly when delegation would add more overhead
> than value.

#### :toolbox:cody
> > Give Cody one fresh, bounded repository task. Cody may explore,
> > edit files, and run relevant tests.
> `m8` `call` `m8` `query` `--new` `@crew/cody/delegated` `{{task|}}`
> * task string
>   The task to complete and any relevant scope or constraints.

#### :toolbox:cody
