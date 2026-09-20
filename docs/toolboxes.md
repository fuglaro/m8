# Toolbox definitions

A toolbox header has one of three forms:

```m8
#### :toolbox:read
> definition content

#### :toolbox:read PAGE_LINES 100

#### :toolbox:read
```

The content-bearing header defines the tool. A blockless header with a
variable and space-separated values adds definition configuration. A bare
blockless header offers the named tool to the agent. Keep these forms separate;
a definition header cannot carry both content and variable configuration.

Definition variables are normalized to `M8_ARG_*`, just like scalar call
parameters. The name is uppercased. Multiple variable headers are allowed.
When a definition, shield, and call provide the same variable, values are
space-concatenated in that order: definition/shield values first, call values
last.

For example:

```m8
#### :toolbox:read
> Read a file or directory.
> `m8` `call` `munge` `read`
> * path string

#### :toolbox:read PAGE_LINES 100
#### :toolbox:read PAGE_BYTES 10000
#### :toolbox:read BYTE_CAP 20000
#### :toolbox:read
```

This syntax keeps a tool definition readable when it has several defaults and
lets an agent override or extend those defaults through ordinary call
parameters.
