# Quiz Bank Quality v3 Design

## Objective

Replace the current model-only quiz-bank quality gate with a reproducible,
dictionary-backed publishing pipeline. The new bank rejects broken word
fragments such as `色列` and `们法`, replaces generic meanings such as `人名`
and `地名`, and makes the official cloud snapshot authoritative on every
successful sync.

Quality has priority over coverage. A short verse may publish no question; a
long verse may publish up to five non-overlapping questions only when all of
them meet the quality gate.

## Repositories and Ownership

`bible-recite-plans` owns the public word-bank data and all offline publishing
tools. `bible_recite` owns on-device validation, staged synchronization and
the local SQLite replacement transaction.

The word-bank repository will add these version-controlled assets:

- `lexicon/bible_terms.v1.json`: curated Biblical people, places, groups,
  titles, objects and theological terms. Each entry has `term`, optional
  `aliases`, `kind`, `meaning`, source/provenance and a safe, answer-free
  definition.
- `lexicon/meaning_rules.v1.json`: prohibited generic meanings and
  category-specific fallback wording. Bare categories such as `人名`, `地名`,
  `专名`, `事物` and their punctuation variants are invalid.
- `tools/audit_quiz_bank_quality.py`: produces JSON and Markdown reports of
  rejected, repaired and review-required questions.
- `tools/repair_quiz_bank_quality.py`: performs only deterministic,
  unambiguous repairs and never invents a word or a definition with a model.

Every lexicon entry must document a redistributable source. The first release
uses a reviewed, repository-owned core lexicon; an external Bible dictionary
may be added only after its license and attribution are recorded in the
repository. Jieba, with this custom lexicon loaded, is an offline audit aid,
not a source of truth and not an Android runtime dependency.

## Word Selection and Repair Rules

For each candidate the tools slice the bundled scripture with the stored
UTF-16 offsets, then evaluate the candidate against the longest overlapping
word-bank term and Jieba token boundaries.

1. A candidate equal to a full approved lexicon term is accepted.
2. A candidate that is a strict substring of, or has an invalid boundary
   inside, an overlapping approved term is rejected as a critical fragment.
3. It is repaired only when exactly one approved term overlaps the candidate,
   that term occurs exactly once in the verse, and its offsets do not overlap
   another retained question. Thus `色列` becomes `以色列`, and `们法` becomes
   `法利赛人`; ambiguous cases are removed and placed in the audit report.
4. Existing function-word, pronoun-edge, reporting-phrase, punctuation,
   numeric-only and UTF-16 checks remain mandatory.
5. The model may propose a candidate, but it cannot bypass these checks.

The publishing target is based on non-punctuation Chinese character count:

| Verse length | Maximum published questions |
| --- | ---: |
| Fewer than 8 characters | 1 only when a strong lexical term exists |
| 8-19 characters | 1 |
| 20-39 characters | 2 |
| 40-69 characters | 3 |
| 70-99 characters | 4 |
| 100 or more characters | 5 |

The effective count is the minimum of this target, five, and the number of
non-overlapping qualified terms. No filler question is generated to reach the
target.

## Meaning Rules

The word-bank meaning overrides model text whenever a term matches. It must
describe the term specifically, be concise, not contain the answer, not quote
or paraphrase the verse and not disclose adjacent narrative. Examples:

- `以色列` uses a safe description of Jacob's descendants as a people/nation,
  rather than the generic label `地名`.
- `法利赛人` uses a safe description of a Jewish religious group known for
  strict Torah tradition, rather than `人名` or a verse retelling.

For a non-lexicon common word, a part-of-speech-specific definition is allowed
only when it includes meaningful distinguishing content. Otherwise the item is
reported for curation and omitted from the published snapshot.

## Publishing Gate

The release pipeline is a single stable-snapshot operation:

1. Stop question generation while a quality release is assembled.
2. Merge the intended source bank, audit every question, apply deterministic
   repairs and omit unresolved candidates.
3. Split the final bank into shards below 10 MiB, generate the index once and
   increment its revision exactly once.
4. Validate every shard against scripture and its index SHA-256/byte count.
5. Fetch each shard from GitHub Raw after the push and compare its bytes and
   SHA-256 to the committed index before announcing availability.

The index adds a required `snapshotMode: "replace"` and
`qualityVersion: 3`. Existing clients safely ignore these extra fields but do
not gain replacement semantics; the v3 app release is required to receive a
clean local bank.

## On-Device Snapshot Replacement

The app downloads and validates every changed shard before changing the live
bank. Validated questions are written to SQLite staging tables associated with
the announced revision. If any download, hash or scripture-position validation
fails, staging is discarded and the active bank remains untouched.

After every shard validates, one SQLite transaction:

1. Detaches historical `quiz_result.question_id` values, preserving result
   date, scope, correctness, streak and achievement inputs.
2. Deletes all current `quiz_question` rows, including old imports, so no
   low-quality question remains available locally.
3. Inserts the staged v3 questions as unanswered current-quality questions.
4. Deletes the staging rows and records the new snapshot revision and hashes.

`quiz_result.question_id` becomes nullable through a migration that rebuilds
the table without a cascading foreign key. Historical statistics continue to
read `quiz_result`'s already-stored scope and correctness fields; an old result
is not attached to a newly inserted question even if SQLite reuses an ID.

The user sees that the question bank was refreshed and that current practice
state restarted, while historical totals, accuracy and achievements remain.
Personal/local imported questions are intentionally removed by this official
full replacement; the existing export action remains the recovery path before
syncing.

## Tests and Acceptance Criteria

Word-bank tests must prove the examples `色列 -> 以色列` and
`们法 -> 法利赛人`, reject ambiguous overlaps, reject bare generic meanings,
and enforce the length-based target with a maximum of five.

App tests must prove that:

- a successful multi-shard replace leaves only the new questions;
- an invalid or unavailable later shard leaves the old active bank intact;
- historical quiz results and statistics survive replacement;
- stale questions cannot be selected after replacement;
- a replacement revision is monotonic and all downloaded shard hashes match.

Release acceptance requires zero critical fragment/generic-meaning findings,
all shard files below 10 MiB, consistent GitHub Raw hashes after publication,
and a successful sync on a device or emulator using the released app.
