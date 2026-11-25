# Codec-owned call identity

Status: planned. No compatibility path; this is a pre-release format change.

## Goal

Keep call/answer matching simple in the framework: the ledger has one opaque,
internal call ID, and every answer refers to that ID. The framework does not
know about provider call IDs or batches. A codec owns the translation between
its provider's IDs and the internal IDs written into the ledger.

Batch processing remains. The codec's parser assigns IDs that preserve the
provider batch relationship; its encoder understands those IDs and rebuilds
the provider's original calls and batch shape. The batch information travels
through the ledger inside the opaque IDs, not as a separate framework-level
`batch_id` field.

## Kept-aside original IDs

Some providers put hidden thought data in a call ID. For OpenAI Completions
and Responses, when a returned provider call ID exceeds 80 characters:

- The parser assigns a short ledger call ID, unique to that call within its
  batch (for example, `1`).
- Immediately after the `📲`, it writes a kept-aside thought record whose
  value is `:call:<ledger-id>` and whose block is a code span containing the
  exact original provider call ID. Example: `💭::call:1` followed by the
  original ID in a code span.
- The parser also gives the codec enough batch identity in the opaque ledger
  call ID to distinguish this call from the same local number in another
  batch.
- On encode, the codec uses the aside to restore the exact provider call ID.
  If there is no matching aside, it decodes the provider ID from the internal
  call ID as appropriate.

The exact `:call:` value remains the discriminator for provider-specific JSON
metadata. A `:call:<ledger-id>` value identifies an original-call-ID aside.
Only the owning codec interprets either block; the framework preserves and
hides kept-aside records structurally, without validating their payloads.

Providers that do not need this behavior need not use these asides. Do not
rewrite short IDs just to apply this mechanism unless a codec needs that to
preserve its batch grouping or avoid collisions.

## Work plan

1. **Inventory the call model and preserve current work.** Review the current
   staged and unstaged diffs first. Trace call IDs through codecs, `m8 parse`,
   outstanding-call lookup, tool execution, results, links, questions, failures,
   and re-encoding. Keep unrelated user changes intact.
2. **Make framework call IDs opaque.** Remove the separate `batch_id` from the
   shared call representation and framework call-value parsing. The framework
   should compare the complete internal call ID consistently for calls and all
   their answers. Keep the existing execution and recovery behavior for
   multiple calls returned together.
3. **Carry codec-owned asides through the response interface.** A codec parse
   must be able to return both its opaque internal call ID and an optional
   kept-aside value/content pair for the original provider ID. The shared
   response/command and conversation paths write that record immediately after
   the call without interpreting its payload. Keep this separate from the
   existing JSON call metadata, which is also an aside but has its own
   discriminator and meaning.
4. **Define codec-owned internal ID encoding.** For Completions and Responses,
   specify a deterministic, unambiguous encoding that carries enough batch
   identity in each opaque internal call ID to regroup calls on re-encode. Use
   local consecutive IDs for long provider IDs and keep their originals in
   `:call:<ledger-id>` asides. Avoid ambiguous delimiters or collisions; add
   focused parse/encode round-trip tests.
5. **Move batch reconstruction into codecs.** Parsers assign the internal IDs;
   encoders regroup calls from those IDs and restore provider-facing IDs. Keep
   provider call IDs and batches out of framework code. Other codecs retain
   their own ID strategy and need not emit these asides.
6. **Adopt the new aside placement and spelling everywhere.** The
   original-ID aside follows its call. Provider JSON metadata uses exact
   `:call:` and follows the call it belongs to. Update codec fixtures and
   generated parse output; do not add compatibility for the old ordering or
   spelling.
7. **Document and verify.** Update `docs/language.md` and relevant provider
   docs. Test duplicate provider IDs across batches, multiple calls in one
   batch, long and short IDs, aside association, interrupted/outstanding calls,
   tool answers and re-encoding. Run `zig fmt`, `zig build test`, `zig build`,
   and `git diff --check`; inspect the final diff against the user's staged
   changes.

## Definition of done

The framework matches calls and answers only by opaque internal call ID and
has no batch-ID concept. Completions and Responses preserve batch grouping and
restore provider call IDs through codec-owned translation. Long IDs survive
round trips in immediately following kept-aside records. No legacy parser or
compatibility branch remains, and the full checks pass.
