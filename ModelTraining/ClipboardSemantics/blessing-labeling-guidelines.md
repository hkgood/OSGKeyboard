# Blessing intent labeling guidelines

## Definition

Label `blessing = true` when the author directly expresses a good wish,
congratulation, prayer, or hope for a recipient. The recipient may be the
reader, a named third party, a group, or the author.

The label is intentionally broad. It includes:

- Festival, birthday, wedding, anniversary, graduation, promotion, new-job,
  housewarming, newborn, and retirement wishes.
- Short congratulations such as `恭喜`, `恭喜发财`, `Congratulations`, and
  `Congrats`.
- Health, recovery, travel, safety, exam, competition, career, and general
  good-luck wishes.
- Good-night and good-day wishes when they express a desired outcome, such as
  `祝你好梦` or `Hope you have a wonderful day`.
- Religious or spiritual prayers directed toward a recipient.
- Wishes expressed for a third person, such as `我衷心祝愿她早日康复`.

## Negative boundaries

Label `blessing = false` when the text only:

- Requests, searches for, or discusses how to write a blessing.
- Thanks someone for a blessing already received.
- Mentions that other people sent blessings.
- Describes a celebration without wishing anyone well.
- Quotes or documents a blessing as an example.
- Greets someone without expressing a desired outcome.
- Gives positive feedback or praise without a wish or congratulation.
- Contains a lexical collision such as a title, name, product, or historical
  reference that happens to include a blessing keyword.

## Context-dependent cases

Annotators must use surrounding context when available:

- Sarcastic congratulations are negative unless the product intentionally
  treats the surface utterance as reply-worthy congratulations.
- `祝我好运` and equivalent self-directed wishes are positive.
- Conditional or unrealized intent such as `等会儿再祝他生日快乐` is negative
  until the text actually expresses the wish.
- A message may be both `blessing` and another intent. For example, a wedding
  invitation containing `祝你们幸福` is both an invitation and a blessing.

## Annotation process

1. Normalize only invisible whitespace; preserve wording, punctuation, and
   emoji for labeling.
2. Two annotators label every golden-set record independently.
3. Disagreements are adjudicated by a third reviewer using this document.
4. Record the boundary category and adjudication reason, not only the binary
   label.
5. Keep all evaluation examples isolated from generation prompts, training
   sources, and active-learning exports.

## Release evaluation

The dedicated blessing benchmark must contain:

- At least 3,000 Chinese and 1,500 English human-reviewed records.
- Equal positive and hard-negative strata for diagnostic metrics.
- A separate natural-prevalence calibration set for threshold selection.
- At least 100 records for each major positive and negative boundary category.

The release gate is precision at least 0.95, recall at least 0.85, and F1 at
least 0.90 on the adjudicated benchmark, with no major boundary category below
0.80 F1.
