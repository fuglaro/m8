#### :runner:bash
> `m8` `call` `bash` `-e` `-c` `{{CODE}}` `bash`

#### :runner:bash raw
> `bash` `-e` `-c` `{{CODE}}` `bash`

#### :toolbox:example
> > A fenced tool uses the framing runner and answers in m8.
> ```bash
> printf 'hello from a tool\n'
> ```

#### :shield:example
> ```bash raw
> exec "$@"
> ```

#### :toolbox:example
