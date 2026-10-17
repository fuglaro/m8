# Toolbox definitions

A toolbox header has one of three forms:

```m8
#### :toolbox:read
> definition content

#### :toolbox:read page_lines 100

#### :toolbox:read
```

#### :toolbox:read
> definition content

#### :toolbox:read page_lines 100

#### :toolbox:read

The content-bearing header defines the tool. A blockless header with a
variable and space-separated values adds definition configuration. A bare
blockless header offers the named tool to the agent. Keep these forms separate;
a definition header cannot carry both content and variable configuration.

Definition variables use the logical name between double underscores,
just like scalar call parameters: `page_lines` becomes `__page_lines__`.
The original capitalization is preserved. Multiple variable headers are
allowed. When a definition, shield, and call provide the same variable,
values are space-concatenated in that order: definition/shield values first,
call values last.

For example:

```m8
#### :toolbox:read
> Read a file or directory.
> `m8` `call` `m8` `munge` `read` `{{page_lines|--page-lines}}` `--` `{{path|}}`
> * path string

#### :toolbox:read page_lines 100
#### :toolbox:read
```

#### :toolbox:read
> Read a file or directory.
> `m8` `call` `m8` `munge` `read` `{{page_lines|--page-lines}}` `--` `{{path|}}`
> * path string

#### :toolbox:read page_lines 100
#### :toolbox:read

A variable reaches a command the way a call's own values do: in the
environment, and as flags wherever the command line names it.

This syntax keeps a tool definition readable when it has several defaults and
lets an agent override or extend those defaults through ordinary call
parameters.
