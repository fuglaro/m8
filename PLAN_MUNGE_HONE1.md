# Pagey tools: pagination and context-budget plan

## Purpose

The `pagey` tool surface exposes file reading, directory listing, editing, and
searching through `m8 call munge`. The common model is that answers are made of
logical pages. Pages are useful coordinates for an agent: a page number is
coarse and reasonably stable, while the content inside the page supplies the
precision needed for follow-up reads and edits.

There are three deliberately separate controls:

- `M8_ARG_PAGE_LINES` — logical page line target; default `100`.
- `M8_ARG_PAGE_BYTES` — logical page byte target; default `10000`.
- `M8_ARG_BYTE_CAP` — answer-size/context target; default `20000`.

`PAGE_LINES` and `PAGE_BYTES` construct page boundaries. `BYTE_CAP` does not
change those boundaries. It decides how many already-defined whole pages are
returned in one answer. It is a context-budget target, not a hard output or
memory-safety limit:

- the first selected page is always returned;
- subsequent pages are omitted if adding one would exceed the target;
- an individual page may itself exceed the target;
- the trailer is not included in the content-byte accounting.

## Framework contract

Tool-call parameters and definition-provided values are two ways of supplying
the same environment inputs. Both use the `M8_ARG_` namespace.

Definition values are space-concatenated with call values of the same name,
with definition/shield values first and call values after them. This avoids a
special compatibility path and makes a tool parameter adjustable either by the
agent definition or by the call.

Toolbox headers have three separate forms:

```text
#### :toolbox:read
> tool definition content

#### :toolbox:read PAGE_LINES 100

#### :toolbox:read
```

They mean definition, definition variable, and offer/activation respectively.
A variable must not be combined with a content-bearing definition header.
Multiple variables use multiple headers.

## Implemented

### Environment plumbing

- Definition-level tool variables normalize to `M8_ARG_*`.
- Shield variables normalize to `M8_ARG_*`.
- Same-name tool, shield, and call values merge with spaces instead of being
  overwritten.
- Toolbox definitions support multiple separate variable headers.
- `pagey.md` uses the separate-header form for page settings.

### File reading

- Files have configurable logical pagination.
- Existing line-aware and character-aware page splitting remains the basis.
- `M8_ARG_PAGES` selects ranges and anchored ranges.
- Whole-page byte-cap behavior is retained.
- Page help and defaults describe the three settings.

### Directory reading

Directory listings now use the same broad page model as files:

- entries are sorted first;
- a cheap pre-pass assigns rows to logical pages using representative size
  estimates;
- selected page rows are rendered into the response;
- custom page dimensions and page selection work;
- whole-page answer-cap behavior works;
- the first selected page is retained even when it exceeds the target;
- missing files are reported as `(no longer here)`;
- changed types are rendered according to the type found during rendering;
- symlink targets are retained when available and missing targets are reported.

The estimates intentionally use ordinary representative widths rather than
separate code-file and README-file policies or extreme upper bounds. Actual
rendering is allowed to drift above or below the target.

### Scan page shape

Scan metadata and match placement now use `M8_ARG_PAGE_LINES` and
`M8_ARG_PAGE_BYTES`, rather than fixed pagination constants. Scan still uses
`M8_ARG_BYTE_CAP` for its existing file-result cap.

### Validation

`zig build test` passes after the current changes. Tests cover file and
directory pagination, toolbox/shield environment normalization, separate tool
variable headers, configurable scan/file pagination, and scan-result groups.

## Scan-result pagination

Scan pages are pages of search results, not source-file pages:

- each source-file page's matches form one complete result group;
- groups are never split by `M8_ARG_BYTE_CAP`, even when oversized;
- continuation groups repeat file context and say when they continue mid-file;
- `M8_ARG_PAGES` selects scan-result pages, while source page numbers remain
  the coordinates printed inside each result;
- the first selected result is always retained and trailers are excluded from
  cap accounting.

## Complete tests and documentation

The remaining coverage is lower-level integration coverage for degenerate
`BYTE_CAP` calls, directory metadata edge cases, and environment merge
ordering. Keep `CONFIRM_LATER.md` for non-blocking design notes, not as a
substitute for this implementation plan.

## Design decisions recorded

- Directory listings are documents and should be directly paginatable; agents
  should not be forced to use scan merely to explore a large directory.
- Rich file metadata in listings is retained because it lets an agent decide
  which files and page ranges are worth reading.
- Directory page assignment uses estimates so unreturned file contents are not
  required merely to decide page boundaries.
- Code-like and README-like files do not receive separate policies; the
  estimate is intentionally simple and representative.
- `BYTE_CAP` protects agent context rather than preventing output overflow.
- Logical page boundaries are controlled by page settings, not by the answer
  cap.
- Scan pagination is pagination of result groups, not pagination of the files
  being searched.
