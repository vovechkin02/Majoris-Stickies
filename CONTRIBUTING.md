# Contributing to Stickies

Build and test on Debian 13 using the commands in [README.md](README.md).
Original code and documentation follow
[Majoris Engineering Standards v1.8](docs/engineering-standards-v1.8.md):
American English, Valadoc for all handwritten declarations, explicit
ownership, Vala `var` when type inference is safe, multiline control flow,
and test names describing observable behavior.

Keep SQL and domain logic outside GTK; keep UI composition in XML resources
where feasible. Any new media capability should use the shared Majoris Image
framework rather than installing a second image decoder. Update architecture,
release qualification, and tests when behavior changes.
