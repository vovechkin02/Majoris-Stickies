# Majoris Cross-Project Engineering Standards

**Document version:** 1.8  
**Status:** Organization-wide engineering standard  
**Applies to:** Majoris applications, reusable libraries, system components, command-line tools, build tooling, tests, and Debian packaging  
**Primary languages:** C, C++, Vala, Python, Meson, XML, and shell  
**Language for all original source and documentation:** American English (`en-US`)  
**Revision 1.8:** Establishes mandatory, tool-recognizable declaration-level documentation for all handwritten classes/types, methods/functions, constructors, properties, signals, and externally accessible members, regardless of visibility. Defines language-specific Valadoc, gtk-doc/gi-docgen, Doxygen, and PEP 257 conventions, migration requirements, meaningful-content checks, documentation coverage reporting, and compatibility safeguards. Preserves the v1.7 README template, v1.6 GoF and Vala `var` policies, and all earlier standards.
**Revision 1.7:** Defines a consistent, source-verifiable README structure for all Majoris projects, including real build instructions, supported features and formats, public API and usage references, compatibility, packaging, security, testing, documentation and status. Library, application, service and CLI differences are explicitly accommodated. Preserves all v1.6 GoF and Vala `var` policies.
**Revision 1.6:** Makes intent-driven Gang of Four (GoF) design-pattern governance enforceable across Majoris repositories, including participant naming, interface and composition boundaries, a complete applicability catalog, architecture review evidence, safe migration, and anti-pattern detection. Establishes Vala `var` as the default for clearly inferred local variables with mandatory explicit-type exceptions for contracts, ownership, nullability, and numeric intent. Preserves the v1.5 testing and GUI geometry rules, the v1.4 formatting policy, and all earlier standards.
**Revision 1.5:** Adds cross-project rules for test filenames and case names, Meson test names and stable qualification identifiers, meaningful test granularity, and deterministic GUI test-window geometry. Retains the v1.4 multiline formatting rules, v1.3 test structure policy, and all prior standards.

> **Purpose.** Establish one maintainable set of engineering conventions across Majoris repositories. This document governs source organization, identifiers, ordering, formatting, API/ABI stability, comments, ownership, error handling, security, performance, tests, build systems, packaging, and review. It is intended to be included with Codex implementation and audit tasks.
>
> **Non-goal.** Standardization must not silently change the behavior of a working application. A cleaner implementation is not an excuse to alter numerical output, user interactions, serialized files, build outputs, APIs, resource limits, security guarantees, or default settings.

## 0. How to apply this standard

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** have specific meanings:

- **MUST / MUST NOT:** required for new work, subject to explicitly documented exceptions.
- **SHOULD:** preferred in normal circumstances; alternatives require a concise technical rationale.
- **MAY:** optional when it provides measurable value.

### 0.1 Precedence

If guidance conflicts, apply these rules in order:

1. Safety, correctness, upstream API contracts, language/toolchain requirements, and file-format/protocol standards.
2. Existing public API/ABI, GObject introspection, serialized data, configuration keys, installed paths, and compatibility promises.
3. Project-specific `CONTRIBUTING.md` or documented exceptions approved for that repository.
4. This shared standard.
5. Local formatting preferences that are not formally documented.

**Do not rename an external symbol or standardized spelling to satisfy American English.** Examples: `G_IO_ERROR_CANCELLED`, third-party functions and enums, CSS properties, upstream protocol names, MIME types, and file format identifiers.

### 0.2 New code vs. existing code

- New code MUST conform to this standard.
- Modified code SHOULD be standardized within the smallest sensible scope.
- Repository-wide reformatting MUST be a separate, reviewable commit from behavioral changes.
- Large-scale renames MUST include an impact inventory and integration validation before being applied.
- Generated code, vendored dependencies, upstream snapshots, migration history, and binary fixtures MUST NOT be reformatted indiscriminately.
- If an existing project cannot immediately comply, record a **bounded exception** and a migration plan; do not knowingly break builds for cosmetic uniformity.

### 0.3 Required quality gates

A change is ready for review only when its applicable build, lint, regression, security, package, and API checks pass. If an environment cannot run a check, report it as **not run**, not **passed**.

### 0.4 Domain-neutral scope and examples

This standard applies equally to desktop applications, command-line programs, system services, shared libraries, background workers, installers, build utilities, and tests. Examples MUST use generic components such as requests, tasks, records, configuration, storage, and services, rather than assuming a particular Majoris application or its specialist technologies.

- Examples are **illustrative patterns**, not names or directories that every project must adopt.
- When a rule applies only to a specific technology (GTK, GObject, Debian, etc.), label that condition explicitly.
- Project-specific protocols, file formats, media pipelines, hardware features, and optimization thresholds belong in the **owning repository's** architecture and test documents, not in this organization-wide standard.
- Do not make application-specific processing stages, libraries, or hardware requirements a general standard for all projects.

---

## 1. Engineering principles

1. **Correctness first.** Preserve observable behavior and explicit contracts.
2. **Readable before clever.** Clear control flow is preferred to compressed, overly abstract code.
3. **Single responsibility.** Organize modules by coherent responsibilities, not arbitrarily small files or classes.
4. **One source of truth.** Avoid duplicated flags, protocol definitions, capability lists, constants, configuration settings, and business logic.
5. **Explicit ownership.** Know which layer owns resources, callbacks, threads, processes, temporary files, and object lifetimes.
6. **Fail predictably.** Validate input, return meaningful errors, and avoid silent degradation of important guarantees.
7. **Measure before optimizing.** Profile real bottlenecks and define a correctness baseline before changing algorithms.
8. **Respect language idioms.** Uniformity should not replace proven GLib, GObject, Vala, C++, Python, Meson, or Debian conventions.
9. **Keep boundaries stable.** Public libraries must not expose internal implementation details unnecessarily.
10. **Favor existing infrastructure.** Reuse shared services and established GNOME libraries instead of creating competing implementations.
11. **Apply design patterns by intent.** Follow the GoF principles and the responsibilities of any applicable chosen pattern strictly, while refusing gratuitous pattern classes or renaming that would break compatibility. See §3.5.

---

## 2. Language, terminology, and naming

### 2.1 American English

Use American spelling in **new project-owned** names, comments, logs, documentation, tests, and developer messages:

| Avoid | Use |
|---|---|
| `colour`, `colour_label` | `color`, `color_label` |
| `centre`, `centred` | `center`, `centered` |
| `neighbour`, `neighbouring` | `neighbor`, `neighboring` |
| `catalogue` | `catalog` |
| `serialise`, `serialisation` | `serialize`, `serialization` |
| `initialise` | `initialize` |
| `normalise` | `normalize` |
| `optimise` | `optimize` |
| `behaviour` | `behavior` |
| `grey` | `gray` |
| `cancelled`, `cancelling` in ordinary prose | `canceled`, `canceling` |

**Exceptions:** preserve external identifiers, user-visible product names, proper names, specifications, imported APIs, backwards-compatible keys, serialized field names, and pre-existing public symbols until a deliberate migration is approved. Never globally search-and-replace without classification.

### 2.2 Identifiers by language

| Category | C | C++ | Vala | Python | Meson |
|---|---|---|---|---|---|
| Functions/methods | `snake_case` | `snake_case` | `snake_case` | `snake_case` | `snake_case` variables |
| Local variables | `snake_case` | `snake_case` | `snake_case` | `snake_case` | `snake_case` |
| Types/classes | `PascalCase` | `PascalCase` | `PascalCase` | `PascalCase` | n/a |
| Enums/constants | `UPPER_SNAKE_CASE` | `UPPER_SNAKE_CASE` for enumerators/macros; named `constexpr` per project | `UPPER_SNAKE_CASE` | `UPPER_SNAKE_CASE` | descriptive names |
| Filenames | `kebab-case.c/.h` | `kebab-case.cpp/.hpp` | `kebab-case.vala` | `snake_case.py` | `meson.build` / `meson.options` |

Prefer descriptive, action-oriented function names: `parse_request()`, `validate_options()`, `invalidate_cache()`, `cancel_operation()`. Name predicates `is_ready`, `has_changes`, `can_write`, and `supports_feature`. Use `create_`, `load_`, `find_`, `get_`, `set_`, `update_`, `remove_`, and `release_` consistently where meanings warrant them.

Avoid generic exported C names such as `open`, `render`, `utils_init`, or `helper`. Exported C functions **MUST carry a unique library/subsystem prefix** to avoid link collisions. The prefix can be subsystem-specific and brand-neutral (for example, `taskstore_load_record`) while the distributed product remains branded Majoris. Private `static` helpers need no unnecessary product prefix.

Avoid redundant naming such as `TaskRecord.task_record_id`; prefer `TaskRecord.id` when the meaning is clear. Do not use single-letter names beyond brief index/math scopes. Do not encode types in names (`str_name`, `i_count`) when the type system already communicates them.

### 2.3 Product identity vs. implementation identity

- Product/repository names, Debian package identifiers, desktop IDs, D-Bus names, executable names, application IDs, install paths, and copyright notices MAY retain `Majoris`.
- Internal functions, methods, private classes, and local variables SHOULD describe their responsibility without unnecessary branding.
- Public namespaces, GType names, exported C symbols, VAPI names, GIR namespaces, and `.pc` filenames are **compatibility surfaces**. Renaming them requires an explicit ABI/API migration, not a cosmetic sweep.
- Preserve upstream/library naming exactly, even when its spelling or casing differs.

### 2.4 Numeric and unit names

Specify units in ambiguous values: `timeout_ms`, `duration_us`, `cache_bytes`, `width_px`, `scale_factor`, `retry_count`. Do not mix units silently. Prefer typed enums over magic integers for status, policy, priority, format, and capability values.

### 2.5 GoF participant and implementation naming

**Rule: name a type for the responsibility it actually implements, not for the pattern an author wishes it resembled.** Where a GoF pattern is deliberately adopted, its participant names and module boundaries MUST make the intended contract discoverable without exposing unnecessary implementation details.

| Participant | Preferred naming principle | Examples (illustrative only) |
|---|---|---|
| Abstraction/interface | Describe capability or business-facing contract | `RecordSource`, `TaskExecutor`, `FormatReader` |
| Concrete strategy | Name the algorithm, policy, or backend | `CachedRecordSource`, `LocalTaskExecutor` |
| Adapter | Indicate the external system adapted when useful | `LegacyStoreAdapter`, `RemoteSourceAdapter` |
| Factory / builder | Use the role suffix only when construction is its responsibility | `ConnectionFactory`, `RequestBuilder` |
| Decorator / proxy | Use suffix where it distinguishes a true wrapper | `CachingSourceDecorator`, `PermissionProxy` |
| Facade | Prefer the name clients recognize; `Facade` suffix is optional | `DocumentService`, `StorageFacade` |
| Command | Name the action represented by the object | `SaveRecordCommand` |
| State | Name the behaviorally distinct state; not a mere status value | `WaitingState`, `ExecutingState` |
| Observer | Name event source, listener contract, or concrete listener by purpose | `TaskListener`, `StatusObserver` |
| Composite / leaf | Use the domain model, not mandatory `Composite`/`Leaf` suffixes | `FolderNode`, `FileNode` |

- C/C++/Vala class/interface names MUST use `PascalCase`; members and filenames MUST follow §2.2. Do not add redundant product prefixes to internal symbols.
- A pattern does **not** impose mandatory suffixes such as `Strategy`, `Factory`, `Singleton`, `Manager`, `Impl`, `Base`, `Concrete`, or `Handler`. Require a suffix only if it conveys a useful, accurate role distinction.
- **Public compatibility names prevail.** Public namespaces, GType names, C symbols, GIR/VAPI interfaces, signals, properties, D-Bus names, schema keys, serialized discriminator strings, filenames at installed paths, and worker protocol tokens MUST NOT be renamed for pattern purity.
- String tokens that represent a **protocol identity** are not equivalent to local behavioral switches: retain serialized compatibility even when private code uses an enum, capability, or interface. Do not replace a public-facing name or wire token without a versioned migration.
- An internal strategy/adapter interface MUST use capability- and domain-oriented method names, not copies of one concrete backend's private API. Stable interface methods express common semantics, errors, cancellation, and ownership.
- The principal public/internal type SHOULD be discoverable from its owning `kebab-case` Vala/C/C++ filename, but related private helpers MAY remain together when that improves cohesion. Do not require one file/class per role or force pattern-specific directory trees.


---

## 3. Repository structure and file responsibilities

### 3.1 General structure

Use this as a **reference layout**, not a requirement to add empty folders:

```text
Project/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── .editorconfig
├── .clang-format                 # when C/C++ is present
├── pyproject.toml                # when Python tooling needs it
├── meson.build
├── meson.options                 # only when needed
├── src/
│   ├── core/                    # reusable domain logic
│   ├── gtk/                     # GUI and presentation, if applicable
│   ├── services/                # runtime integrations, if applicable
│   └── app/                     # application entry points, if applicable
├── native/                      # focused C/C++ integrations, if applicable
├── include/                     # public C headers, if applicable
├── vapi/                        # Vala bindings, if applicable
├── data/                        # .ui, GResource, schemas, desktop metadata
├── tests/
│   ├── meson.build
│   ├── fixtures/                # checked-in inputs and manifests
│   ├── support/                 # fixture generators and test helpers
│   ├── unit/                    # focused behavioral checks
│   ├── integration/             # cross-component checks
│   ├── security/                # untrusted input and isolation, if needed
│   ├── extended/                # stress and long-running checks, if needed
│   ├── benchmarks/              # reproducible measurements, if needed
│   └── release/                 # installed/qualification checks, if needed
├── examples/                     # public-API consumers, if applicable
├── docs/
├── tools/                        # Python/shell developer utilities
└── debian/                       # Debian source packaging, if shipped
```

A library and an application do not need identical directory trees. Repository layout MUST reflect actual component boundaries and dependency direction.

### 3.2 File scope

- A file SHOULD have one cohesive purpose; avoid `utils.c`, `misc.vala`, and all-purpose manager classes unless the operations really form a subsystem.
- Keep public API declarations separate from private implementations.
- Keep GUI types out of headless/core libraries unless the library's documented purpose requires GUI integration.
- Keep code generated by Meson, Vala, GIR, protocol compilers, and other tools in build directories.
- Keep tests and fixtures close enough to their components to maintain traceability, while avoiding test-only code in production libraries.
- Organize by functionality, not only by language: `settings/`, `storage/`, `network/`, `notifications/`, `services/` may be better than one undifferentiated `src/`.
- Test-source placement SHOULD follow the same responsibility-first principle. See §17.5–§17.11 for the policy on directory size, implementation language, shared support code, and migration.

### 3.3 When to split a module

Split a class/file when it simultaneously owns unrelated lifecycles, crossing two or more clear boundaries (for example, subprocess launching, request serialization, persistent storage, and GTK event handling). File length alone is **not** a defect; avoid extracting trivial wrappers that make control flow harder to follow.

When splitting:

1. Write down invariants and the public interface first.
2. Extract one responsibility at a time.
3. Keep ownership and cancellation contracts explicit.
4. Preserve existing externally visible names and behavior.
5. Run focused and full tests after each extraction.

### 3.4 Entry points, `main()`, and application bootstrap

**Principle: keep entry points thin, but not artificially empty.** The `main()` function should establish the process lifecycle and delegate substantial work to cohesive, testable components. This applies to graphical applications, CLI tools, worker processes, background services, test executables, and small Python utilities.

#### 3.4.1 Responsibilities and size

An entry point SHOULD do only the startup/shutdown coordination that is useful to see together:

1. Parse or hand off command-line arguments and select a documented process mode.
2. Initialize process-wide facilities that genuinely must be initialized once (for example, localization, logging, or a required framework runtime).
3. Construct the top-level application, service host, or command dispatcher.
4. Register necessary top-level hooks or signals and establish the application lifecycle.
5. Transfer control to the application/main loop/dispatcher.
6. Return an intentional exit status and perform necessary top-level shutdown.

It SHOULD NOT accumulate domain logic, data transformation, business rules, database queries, network calls, large GTK widget trees, complex settings migrations, protocol parsing, recurring timer management, or individual feature workflows. Those belong in appropriately named modules with clear ownership and error contracts.

**Size guideline (not a hard limit):** aim for roughly **10–60 readable lines** of nontrivial startup logic in `main()`. At **more than ~80 logical lines**, review its responsibilities; at **more than ~120**, normally extract cohesive phases unless the code is an intentionally straightforward CLI dispatcher or test registration file. Count meaningful statements and branches rather than blank lines, comments, or formatting. **Do not split a clear 25-line function into several pointless wrappers merely to meet a number.** Likewise, do not hide a 400-line startup routine inside a single `initialize_everything()` call and call that a refactor.

A file named `main.c`, `main.cpp`, `main.vala`, or `__main__.py` SHOULD normally contain the entry point and only the smallest required adjacent bootstrap code. Do not put the entire application in that file merely because execution starts there. The actual number of lines in such a file is less important than the concentration of unrelated responsibilities.

#### 3.4.2 Startup and shutdown phases

Where startup is nontrivial, use clearly separated, named phases with explicit order and failure behavior:

1. **Parse:** validate CLI arguments without performing costly application work; return usage errors consistently.
2. **Preflight:** verify mandatory configuration, runtime capabilities, and dependencies. Perform only checks necessary before creating the application.
3. **Construct:** create the application/service graph and establish dependency ownership, preferably without hidden global state.
4. **Start/run:** activate the GUI main loop, command handler, or service dispatcher; load optional or expensive features lazily where safe.
5. **Stop:** cancel outstanding operations, disconnect signals, release owned resources, flush critical state, and return an appropriate exit status.

Use platform/framework lifecycle hooks instead of building a parallel lifecycle inside `main()` (for example, `GApplication`/`GtkApplication` startup, activate, open, command-line, and shutdown handlers). Document any ordering that is safety-, compatibility-, or protocol-critical. Avoid hidden side effects in global initializers, constructors, module imports, or code executed simply by linking a library.

Errors MUST propagate through the defined layer contract. A recoverable per-request failure must not be treated as fatal process startup. Conversely, a failed mandatory sandbox or security setup must not be silently ignored. Exit codes SHOULD distinguish success, argument/configuration errors, and runtime failure where appropriate. Emit a diagnostic once at the owning boundary rather than repeatedly logging and rethrowing the same error.

#### 3.4.3 GTK4, GLib/GIO, and Vala applications

For a GTK application, `main()` SHOULD create the `Gtk.Application`/`Adw.Application` instance and invoke `run()`. Put window creation and application-wide lifecycle work in the application class and its documented callbacks; keep UI layout in XML templates. Do not synchronously perform expensive file I/O, database migrations, device scanning, or network calls on the GTK main thread during startup.

Illustrative Vala entry point:

```vala
int main (string[] args) {
    return new ExampleApplication ().run (args);
}
```

Here, `ExampleApplication` is a separately implemented, testable application type—not a single catch-all class containing every feature. For libraries, do not introduce a fake `main()`; expose explicit, documented initialization only if necessary. For service applications, use the corresponding `GApplication` command-line, activation, and shutdown mechanisms instead of manually implementing an inconsistent event loop.

#### 3.4.4 C and C++ command-line programs and native workers

For C, keep initialization and option parsing close to the entry point only when they remain simple. Prefer `GOptionContext` or another established parser for nontrivial GLib tools, named exit-status constants, and one well-defined cleanup/ownership strategy. Expensive or protocol-specific work belongs in `run_command()`, a service object, or dedicated operation modules—not in an oversized `main()` switch.

For C++, let RAII own resources and catch exceptions **at the top-level process or C ABI boundary**. An entry point can call a cohesive `run_application(argc, argv)` and translate unhandled exceptions into an error exit code, but `run_application()` MUST NOT become an unreviewable replacement monolith. Do not allow C++ exceptions to escape exported C callbacks or GLib boundaries.

For sandboxed workers, the entry point SHOULD establish the validated process environment, argument/request transport, resource and sandbox requirements, and dispatch to dedicated operation handlers. Preserve the trust boundary: untrusted payloads must be parsed and processed only within the intended isolated environment. The entry point must not disable security mechanisms merely to simplify startup.

#### 3.4.5 Python tools and test runners

Python tools SHOULD define `main(argv: ...) -> int` (using typing supported by the project's minimum Python version) and use the standard guard:

```python
if __name__ == "__main__":
    raise SystemExit(main())
```

The module should remain import-safe: parsing arguments, starting subprocesses, writing files, generating fixtures, and running tests must not occur merely on import. Keep parsing and dispatch in `main()`; move substantive operations into importable, testable functions. Prefer `argparse`, `pathlib`, bounded subprocess calls, and explicit exit codes.

For C/GLib test runners, `main()` MAY contain straightforward `g_test_init()`, test registration, and `g_test_run()` calls. Complex fixture setup and individual assertions MUST reside in dedicated test functions or fixtures. In Python, prefer normal test framework discovery and fixture mechanisms; do not build an oversized homegrown test runner without a demonstrated need.

#### 3.4.6 Structure and Meson integration

Prefer a distinct bootstrap source (`src/app/main.vala`, `src/app/main.c`, `src/worker/main.vala`, or an equivalent project-appropriate location) and separate modules for application lifecycle, CLI parsing, services, GUI presentation, and worker operations **where those responsibilities actually exist**. Do not create empty abstractions or extra files for a tiny single-purpose utility.

In Meson:

- List entry-point sources explicitly in the **executable's** source list, grouped separately from reusable core sources.
- Reusable libraries MUST NOT accidentally compile or export a process `main()`.
- Keep worker, GUI, CLI, and test entry points in their own executable targets; avoid accidental duplicate symbols.
- Place `executable()` declarations after the libraries/dependencies they consume; keep source lists grouped by responsibility and alphabetized within groups.
- Put startup-only dependencies on the executable when possible, not unnecessarily on a reusable headless library.
- Test installation and invocation of the real executable in addition to unit-testing its underlying components.

#### 3.4.7 Refactoring and verification

When reducing an oversized entry point, first map every current initialization dependency, environment setting, signal connection, teardown operation, exit code, and user-visible side effect. Extract cohesive operations in small commits while preserving startup order, ownership, error reporting, and shutdown semantics. Avoid replacing direct readable steps with unnecessary factories or service locators.

Tests SHOULD cover successful startup, help/version and invalid arguments, missing configuration/dependencies, shutdown/cancellation, signal-driven termination where applicable, and failure paths involving partially initialized resources. GUI tests SHOULD verify repeated activation/open requests and single-instance behavior. Worker tests SHOULD verify sandbox initialization failures, malformed requests, and clean process exit.

A review MUST ask: **Can a maintainer understand how the process starts, runs, and stops by reading the entry point and its clearly named lifecycle calls—without finding the application's feature logic implemented there?**

### 3.5 Gang of Four design-pattern governance (mandatory where applicable)

**Purpose.** Majoris code MUST honor the GoF principles and participant contracts whenever a pattern addresses a real variation or recurring design problem. "Strict adherence" means **faithful intent, correct structure, naming, ownership, substitutability, and observable behavior**; it does **not** mean instantiate all 23 patterns, introduce interfaces for one immutable implementation, or construct pattern hierarchies to meet a checklist. Avoiding an inapplicable pattern is often the compliant choice.

#### 3.5.1 Governing GoF principles and related SOLID constraints

1. **Program to interfaces, not implementations:** when consumers need interchangeable behavior, depend on a stable interface/abstract contract and inject or select implementations at a cohesive boundary. Direct concrete dependencies are permitted where implementation choice is intentionally fixed, interop constrains the API, or indirection would add measurable cost without a variation point.
2. **Favor object composition over class inheritance:** compose independent capabilities; inherit where a genuine, substitutable `is-a` relationship and framework contract require it (for example, GTK/GObject types). Do not use inheritance merely to reuse unrelated implementation details.
3. **Encapsulate what varies:** confine backend choice, algorithms, policy, serialization, filesystem details, and platform variation to their owning boundaries. Do not let multiple callers inspect implementation names and branch on them for behavior. Capability flags or enums may be preferable for small closed sets; an interface is preferred for independently evolving implementations.
4. **Single responsibility (SRP):** one coherent reason to change per component, not an arbitrary line-count limit. Split only where unrelated lifecycles or modification reasons make ownership and review difficult.
5. **Open/closed (OCP):** new independently supported implementations SHOULD be added at an explicit extension point rather than by editing every consumer. Do not promise extensibility that the protocol or public API cannot support.
6. **Liskov substitution (LSP):** every implementation MUST honor the documented preconditions, postconditions, supported capabilities, failure classification, cancellation, thread context, and ownership of its contract. A subtype must not silently weaken safety or output guarantees.
7. **Interface segregation (ISP):** keep consumer-facing contracts focused; capability-specific methods may be optional through a separate focused interface, not a large collection of invalid default methods.
8. **Dependency inversion (DIP):** high-level orchestration SHOULD not know platform-specific I/O, codec internals, or presentation details. Protocol and hardware boundaries may use small adapters and stable data contracts without adding extra abstract layers.
9. **One source of truth:** capability lists, implementation IDs, serialized tokens, and operation constants MUST be defined or mapped deliberately, not duplicated as unrelated strings and numerical values throughout consumers.
10. **Readability and performance:** choose the simplest idiomatic implementation that satisfies the problem. Avoid a virtual dispatch in a pixel/sample hot loop when it can be resolved once before the loop; avoid allocation-heavy pattern wrappers where a direct function is more reliable.

A design review MUST distinguish a **true GoF pattern instance**, a **pattern-like idiom**, an **intentionally simple conditional**, and **no applicable pattern**. Do not label normal status enums as the GoF State pattern, ordinary request records as Command, or a worker API wrapper as a full Proxy unless it satisfies the defining intent.

#### 3.5.2 Complete applicability catalog (all 23 GoF patterns)

This table is a decision reference, **not** a requirement to implement each pattern. Apply the structural constraints in §3.5.3 only after the stated force exists. All examples are domain-neutral.

| Family | GoF pattern | Apply when | Do not add solely for |
|---|---|---|---|
| Creational | Abstract Factory | Interchangeable, internally consistent families of related objects | One concrete family or a plain constructor |
| Creational | Builder | Construction has optional/validated steps or requires staged assembly | A handful of obvious constructor arguments |
| Creational | Factory Method | A type/creator legitimately delegates product selection to substitutable implementations | Renaming an ordinary helper `Factory` |
| Creational | Prototype | Copying configured objects preserves nontrivial construction state | A normal `copy()` operation with no substitution need |
| Creational | Singleton | Exactly one shared instance is a documented process-wide invariant | Convenience global access or hiding dependencies |
| Structural | Adapter | A third-party or legacy interface must become the application's stable contract | A pass-through class with identical interface |
| Structural | Bridge | Abstraction and implementation are two independently varying dimensions | One fixed abstraction and one fixed implementation |
| Structural | Composite | Leaf and group objects must be processed through the same recursive contract | Flat lists or unrelated object trees |
| Structural | Decorator | Behavior must be layered transparently around a contract | One-off logging better expressed in a helper |
| Structural | Facade | Clients need a stable, simplified entry point over several internals | Masking a monolithic God Object |
| Structural | Flyweight | Large numbers of objects can safely share immutable intrinsic state | Shared mutable state or an unmeasured optimization |
| Structural | Proxy | A stand-in controls access, location, lifecycle, caching, or security under an equivalent contract | Every subprocess client or RPC wrapper by default |
| Behavioral | Chain of Responsibility | Multiple handlers may handle/pass a request under an explicit ordered contract | A fixed two-branch fallback with different semantics |
| Behavioral | Command | An action needs identity, queuing, undo, logging, or deferred execution | A simple operation string or data-only request |
| Behavioral | Interpreter | A small, stable formal grammar warrants object-based evaluation | Standard JSON/XML/protocol parsers or arbitrary scripts |
| Behavioral | Iterator | Collection traversal should not expose its representation | Replacing `foreach` and established collection APIs |
| Behavioral | Mediator | Peer-to-peer component knowledge is causing tangled coordination | Renaming a large controller without reducing coupling |
| Behavioral | Memento | Reversible state must be captured without exposing internals | Arbitrary copying of large mutable resources |
| Behavioral | Observer | Independent subscribers react to state or events | Duplicating GLib/GObject signals with a custom event bus |
| Behavioral | State | Behavior genuinely varies across state objects with valid transitions | A clear fixed enum-based state machine |
| Behavioral | Strategy | Algorithms/providers are interchangeable under one behavior contract | Adding polymorphism to a fixed hot loop |
| Behavioral | Template Method | A stable inherited algorithm has intentional overridable steps | Forcing inheritance where composition works |
| Behavioral | Visitor | New operations vary across a fixed stable type structure | Dynamic protocols, evolving types, or simple switches |

#### 3.5.3 Participant contracts and naming by pattern family

**Creational:**

- A Factory Method/Abstract Factory MUST centralize the varying construction decision, return the promised abstraction, and document failure and ownership. Its clients MUST NOT require knowledge of the selected concrete class unless the contract intentionally permits it.
- A Builder MUST have an explicit validation/finalization boundary, clarify whether reuse is allowed, and not expose partially valid completed objects. Use builders only when their staged state adds value; a typed options object is not automatically a Builder.
- A Prototype MUST define deep/shallow copy behavior, ownership of shared resources, and identity changes. `copy()` alone does not establish the pattern.
- A Singleton MUST be justified by a real global invariant; define thread-safe initialization, test isolation, disposal/process lifetime, and any exposed mutable state. Prefer dependency injection for testable services unless a single instance is required by the contract.

**Structural:**

- An Adapter MUST translate a distinct interface, errors, capabilities, and ownership appropriately; adapters should not leak third-party types through intended neutral boundaries.
- A Bridge MUST demonstrate two independently variable dimensions and separate their contracts; do not use the name simply because C and Vala are both involved.
- A Composite MUST support leaf and group instances under the same documented operations and lifecycle rules. Recursive cycle detection/limits may be necessary for untrusted trees.
- A Decorator/Proxy MUST implement an equivalent client-facing contract, preserve observable semantics, and document any caching, blocking, security, or retry effects. Never silently broaden privileges or weaken errors.
- A Facade MUST be a deliberately narrow entry point; the facade SHOULD delegate real work instead of growing into a second full implementation of the subsystem.
- A Flyweight MUST share **immutable** intrinsic state and maintain clear ownership of extrinsic state. Validate memory benefit before introducing it.

**Behavioral:**

- A Strategy MUST express the common operation and its pre/postconditions in an interface or equivalent private contract. Selection occurs outside the operation's hot path where possible; consumers MUST NOT branch on a human-readable implementation label to invoke backend-specific operations.
- A State implementation MUST own state-dependent behavior and transitions if using the GoF pattern. A simple enum + clear transition logic remains correct when state classes would add no value.
- A Command MUST represent an actionable operation with defined execution, result/errors, and optional undo/queue semantics; a serialized request body is not necessarily a Command.
- An Observer MUST define subscription ownership, delivery context, disconnection, event ordering, reentrancy, and lifetime. Prefer native GObject properties/signals, GTK notify, and GLib event facilities where applicable.
- A Chain of Responsibility MUST define pass/handle behavior, order, termination, cancellation, and whether partial side effects are allowed. Do not relabel fixed error recovery as a generic chain.
- A Mediator MUST reduce coupling among peers, not become an unbounded `Manager` containing all of their domain logic.
- An Iterator MUST preserve the collection's documented traversal, invalidation, and lifetime behavior; prefer native `foreach`/Gee iterators.
- A Memento MUST protect encapsulation while defining snapshot cost, retention and restoration guarantees.
- An Interpreter MUST define a bounded grammar, parsing errors and resource limits; prefer standard parsers when possible.
- A Template Method MUST preserve a genuine base-class algorithm and safe overrides; choose Strategy if runtime composition is what varies.
- A Visitor MUST document the trade-off between adding new operations and adding new element types, including handling of unknown or extended types.

#### 3.5.4 Concrete architectural boundaries

- **Public API boundary:** public GObject types, GIR/VAPI, C symbols, protocols and schema keys are compatibility contracts. Prefer adding/changing private implementation roles; do not alter a published type merely to fit a diagram.
- **Stable domain and presentation boundary:** keep domain processing, I/O, protocol adaptation and GUI presentation in their owning components. Reuse GTK/GObject interfaces and signals rather than adding an unnecessary design-pattern framework around them.
- **Backend variation:** an extensible backend family MUST have a documented selection point, capability validation, and a shared operation contract or a bounded set of explicit capability contracts. Use a private enum for a small, genuinely closed choice when it is clearer; preserve any existing serialized/name identifiers at the boundary.
- **Lifecycle:** every composition edge MUST have an owner, required cleanup, cancellation behavior, and allowed reference direction. Observer subscriptions MUST have a disconnection/lifetime policy. No circular strong-reference ownership without a documented break.
- **Dependency direction:** high-level orchestration owns policy; low-level adapters implement details. Avoid implementation-specific names and data in consumers, unless unavoidable and documented as a bounded exception.
- **Module placement:** group by responsibility and lifecycle (§3.2–§3.3); a pattern does NOT require a separate directory, interface, class, file, framework, or registration service if a smaller idiomatic implementation already meets the same intent.
- **Hot paths:** decide algorithm/backend policy once outside repeated pixel, record or per-element loops when possible. Pattern object creation and virtual dispatch MUST NOT create a measured regression in latency, allocation rate, memory, or throughput.
- **Errors:** alternate implementations MUST preserve the caller's documented error and cancellation contract. Never turn a detected failure into successful fallback unless policy explicitly allows it.

#### 3.5.5 Vala, GObject, C/C++ and Python idioms

- Vala interfaces (`interface`), GObject signals/properties, GLib async methods and GTK controller/lifecycle constructs SHOULD be preferred over hand-rolled equivalents when they express the needed GoF responsibility.
- In Vala, implement object construction and ownership with the correct `Object`/GObject lifetime semantics; do not apply C# garbage-collection assumptions to reference cycles or borrowed data. A private non-GObject helper may be appropriate when a public GType would be unnecessary.
- In C, opaque structs plus function tables/callbacks may express Strategy, Adapter or Bridge without fabricating GObject types; keep C ABI exports namespaced and ownership annotated.
- In C++, RAII and standard containers often satisfy lifetime or Iterator concerns. Do not create wrapper classes to replace existing language facilities.
- In Python, normal modules, protocols, callables and standard collections may satisfy an intent without a Java-style interface hierarchy. Keep test orchestration distinct from production domain behavior.
- **Do not replace an idiomatic, tested implementation with a pattern merely for a superficial class-diagram resemblance.** A compliant review documents the absence of a pattern when a direct solution is more maintainable.

#### 3.5.6 Required architecture decision record for each actual pattern instance

Each repository adopting or modifying a meaningful GoF pattern SHOULD maintain a concise design record in its existing architecture documentation (for example `docs/architecture.md`, not a mandatory new file). Record:

1. **Problem/variation:** what changes independently, and which concrete callers are affected.
2. **Pattern and intent:** the precise GoF name, or state "idiomatic pattern-like design" rather than misclassifying the structure.
3. **Participants:** abstraction, concrete implementations, creator/selector, client, and lifetime owner, as applicable; identify actual types/files.
4. **Dependencies:** which module depends on which interface; identify cross-layer and process boundaries.
5. **Compatibility:** public symbols/types, GIR/VAPI, GObject properties/signals, wire tokens, schemas, persisted data, and installed paths that cannot change.
6. **Execution contract:** ownership, cancellation, thread/main-context requirements, errors, output equivalence, ordering, and performance constraints.
7. **Applicability rationale:** why the selected pattern is simpler/safer than the nearest direct alternative, and whether another implementation is genuinely anticipated.
8. **Verification:** targeted tests, benchmarks when relevant, ABI checks, and any bounded exceptions.

Do not write one design document per trivial helper. A concise table of significant pattern instances is usually sufficient. Do not claim full GoF State/Command/Proxy based only on enum names, operation records, or asynchronous IPC.

#### 3.5.7 Strict review checklist and prohibited anti-patterns

A design-pattern compliance review MUST answer:

- What concrete variation does the chosen pattern encapsulate? Is it a **real requirement** rather than a speculative future?
- Are the claimed GoF participants and contracts actually present? Are the names truthful?
- Can an alternative implementation honor the interface without extra client-side `instanceof`, backend-name string comparisons, or downcasts?
- Does the abstraction preserve output, failure semantics, cancellation, ownership, thread context, and applicable security guarantees?
- Is state/selection policy centralized at its correct boundary? Are capability checks defined once?
- Are GObject/GTK facilities reused instead of duplicated?
- Is the object graph free of avoidable cycles, hidden global state and ambiguous cleanup?
- Does the structure reduce coupling and duplication rather than merely increase file count?
- Do ABI, serialized protocol, public names, and packaging remain compatible?
- Is performance preserved by representative baseline measurements, with appropriate variability and memory peaks?

The following MUST NOT be introduced without a documented, narrowly scoped exception: "God" managers owning unrelated lifecycles; interface-per-class proliferation; meaningless `I`/`Abstract`/`Concrete` naming; unjustified Singleton service locators; decorative Factories/Builders; silent fallback; duplicated event buses; human-readable labels as behavioral discriminators across multiple consumers; abstraction layers in hot loops without evidence; cosmetic renames of compatibility surfaces.

**Adoption is incremental:** preserve a compliant existing composition even if it has no named GoF pattern. If the only reason for a rewrite is that a class diagram looks more like a textbook, do not perform it.


---

## 4. Formatting and declaration ordering — all languages

### 4.1 Baseline

- UTF-8 text, LF line endings, final newline, and no trailing whitespace.
- Spaces for indentation. Defaults: **C/C++/Vala: 4 spaces**, **Python: 4 spaces**, **Meson: 2 spaces**. A repository with a documented GNOME-style two-space C convention MAY retain it for existing code; do not mix styles within a file.
- Target **100 columns** for C/C++/Vala/Meson prose-like lines and **88 columns** for Python. Break long expressions for clarity. External URLs, hashes, generated code, and unbreakable identifiers are exceptions.
- Put spaces around ordinary binary operators and after commas. Do not align unrelated expressions using fragile columns of whitespace.
- Avoid unrelated declarations on one line and compressed multi-statement blocks.
- For project-owned **C, C++, and Vala**, use explicit, multiline braces for control-flow bodies **even when they contain a single statement**. See §4.1.1. Existing external API names and generated code remain exempt.
- Keep one logical operation per statement; avoid clever chains with hidden side effects.
- Avoid anonymous numeric literals for non-obvious limits; define named constants with units.

### 4.1.1 Multiline control flow, braces, and compact statements

**Mandatory for new and standardized project-owned C, C++, and Vala code:** place the opening brace of a control block after its condition, put the body on its own indented lines, and put the closing brace on its own line. This applies even to one-statement branches and early returns. In particular:

- `if`, `else if`, `else`, `for`, `foreach`, `while`, and `do` bodies MUST use braces and MUST NOT put executable statements between `{` and `}` on one line.
- `try`, `catch`, and `finally` bodies MUST be multiline; do not use inline catches or empty inline catch bodies.
- `switch` case bodies and early-exit branches MUST NOT cram several statements onto one line. Case labels need not be wrapped in additional braces unless scoping requires them.
- Simple guard clauses still use braces. Avoid `if (condition) return;`, `if (condition) { return; }`, and `for (...) { operation(); }` in project-owned code.
- For control statements, prefer `} else {` and `} catch (...) {` on one line when consistent with the language's syntax. `do { ... } while (condition);` follows the corresponding language syntax with the body expanded across lines.
- **Function and method implementations** MUST NOT collapse executable bodies onto a single line, including trivial getters, test helpers, or `main()`. Follow the project's function-definition brace placement (for example, GNU C often puts the function's opening brace on the next line); this does not affect the control-flow rule above.
- Empty bodies require a specific reason. Prefer to remove an unnecessary handler/branch; when an intentionally empty block is required, keep it multiline and explain why with a concise comment. Do not use `catch (...) { }` or `if (...) { }` as unexplained placeholders.
- Initializer braces, empty initializer lists, enum declarations, data literals, type declarations, preprocessor macros, and third-party/generated code are **not** executable control-flow bodies. Use the language's normal idiom instead of indiscriminately rewriting every pair of braces.

**Preferred C/C++ example:**

```c
if (!request_is_valid(request)) {
    return FALSE;
}

if (has_pending_work) {
    process_next_request();
} else {
    schedule_retry();
}

for (size_t index = 0; index < item_count; index++) {
    process_item(items[index]);
}
```

**Avoid:**

```c
if (!request_is_valid(request)) return FALSE;
if (has_pending_work) { process_next_request(); } else { schedule_retry(); }
for (size_t index = 0; index < item_count; index++) { process_item(items[index]); }
```

**Preferred Vala example:**

```vala
try {
    yield service.refresh_async(cancellable);
} catch (IOError.CANCELLED error) {
    return;
} catch (Error error) {
    warning("Refresh failed: %s", error.message);
}
```

For **Python**, compound statements and exception handlers MUST use an indented multiline suite: prefer `if condition:
    return` to `if condition: return`. Python has no braces. For **Meson**, put `if`/`else`/`endif`, `foreach`/`endforeach`, and the enclosed statements on separate lines. For **shell**, use multiline `if`/`then`/`fi` and loop bodies for nontrivial logic. These rules prohibit compressed control flow without forcing unrelated language constructs into C-like braces.

### 4.1.2 Blank lines, vertical spacing, and separation

Whitespace MUST communicate a meaningful boundary, not visually inflate a function. The following are defaults for **project-owned, handwritten code**:

- **Inside C, C++, Vala, Meson, and shell functions/blocks:** use **zero or one blank line** between groups of statements. Use one only where it separates meaningful phases, such as validation, processing, and cleanup. Do not insert two or more consecutive empty lines inside a block.
- **At the beginning or end of a block:** do not insert an empty line immediately after `{` or immediately before `}`. For other languages, apply the same principle after an opening construct and before its closing construct.
- **Between C/C++/Vala top-level functions, methods, or cohesive declaration groups:** normally use **one blank line**, except where an established documentation or declaration style requires a clearer separation. Do not scatter several blank lines between short methods or between a declaration and its implementation.
- **Between includes/import groups:** preserve the single blank line needed to distinguish standard-library, third-party, and local headers/modules. Do not remove intentional separation simply to minimize the total line count.
- **Between a documentation comment and its declaration:** do not insert an unrelated blank line. Do not separate a control statement from its opening brace or a closing brace from an attached `else`/`catch` branch with blank lines.
- **Python:** follow PEP 8: **two blank lines** around top-level function/class definitions, and **one** between class methods; use no more than one intentional blank line between logical steps inside a function. Do not flag Python's two top-level blank lines as a violation.
- **Meson:** use one blank line between meaningful dependency, source-list, target, installation, and test-registration sections; no repeated empty lines inside a logical group. Do not insert a blank line between a simple `if` condition and its contents merely for decoration.
- **Markdown and documentation:** headings, lists, and fenced blocks need Markdown-appropriate spacing. These rules are for source code and must not break document structure, license blocks, or generated output.

**Preferred spacing within a function:**

```c
static gboolean
process_task(Task *task, GError **error)
{
    if (!validate_task(task, error)) {
        return FALSE;
    }

    TaskResult result = run_task(task);
    if (!result.success) {
        return FALSE;
    }

    return publish_result(&result, error);
}
```

**Avoid artificial gaps or inline bodies:**

```c
static gboolean process_task(Task *task, GError **error) {

    if (!validate_task(task, error)) { return FALSE; }


    TaskResult result = run_task(task);


    return publish_result(&result, error);

}
```

Do not eliminate meaningful paragraph breaks to satisfy a numerical limit. Conversely, do not use blank lines in place of smaller, more coherent functions when one function contains unrelated responsibilities.

### 4.1.3 Line wrapping, indentation, and automated enforcement

- Preserve readable indentation and the preferred line-width limits in §4.1. Break long argument lists, nested conditions, and chained operations at **logical boundaries** with a consistent continuation indentation. Do not combine several assignments, error checks, returns, or cleanup operations onto one line.
- A simple initializer, declaration, short expression, or single function call **may** remain on one line when within the width limit; the multiline rule applies to **executable bodies and control flow**, not every use of punctuation or braces.
- A formatter may enforce spacing, brace placement, and maximum consecutive empty lines for C/C++. **Vala, Meson, and shell require language-aware review or compatible tools**; do not indiscriminately run `clang-format` over Vala or use regular-expression rewrites that change syntax.
- Formatter output must be reviewed for preprocessor macros, external interfaces, documentation annotations, and language-specific constructs. Apply a **format-only change separately** from behavioral refactoring, and rerun the relevant build and tests.

### 4.2 Variable and constant ordering

At file/class scope, group in this order, when applicable:

1. Public types, enums, and constants (in public header/interface where relevant).
2. Internal types and private constants.
3. Static immutable configuration and lookup tables.
4. Private mutable module state **only when necessary**.
5. Constructors and lifecycle implementation.
6. Methods/functions grouped by responsibility.

Within functions:

- Declare variables as close as practical to first use.
- Initialize variables when declared, unless a documented output-parameter pattern requires otherwise.
- Use the narrowest appropriate scope and visibility.
- Favor immutable declarations (`const`/`constexpr` when legal). Use `unowned`/`weak` only for correct ownership and lifetime semantics; these are **not** immutability qualifiers.
- Group genuinely related locals, never arbitrary alphabetical variables at the top of a long function.
- Keep ownership-related variables and cleanup paths easy to locate.

### 4.3 Function ordering

For C implementation files, the preferred order is:

1. Own header and includes.
2. File-level documentation (if needed), constants, private types.
3. Private forward declarations **only when required**.
4. Small reusable private helpers in dependency order.
5. Public function implementations grouped as they appear in the public header.
6. Module cleanup helpers adjacent to their owning resource/lifecycle.

For C++ classes and Vala classes, keep declarations in a predictable order defined below; group implementation methods by lifecycle and feature rather than sorting every method alphabetically.

**Ordering must never create circular dependencies or require extra fragile forward declarations merely for visual consistency.**

---

## 5. C (GNU11 / GLib / GObject)

### 5.1 Headers and includes

A C source file SHOULD include its **own public/private header first**, proving that header is self-contained. Then use visually separated, alphabetically sorted groups:

1. Own header: `"request-store.h"`.
2. C standard / POSIX headers: `<stdint.h>`, `<string.h>`, etc.
3. GLib/GIO/GObject/GTK headers.
4. Other third-party libraries required by the component (for example, SQLite or libsecret).
5. Other project-local headers.

```c
#include "request-store.h"

#include <stdint.h>
#include <string.h>

#include <gio/gio.h>
#include <glib.h>

#include <sqlite3.h>

#include "request-types.h"
#include "storage-errors.h"
```

- Include what is used directly; do not depend on transitive includes.
- Public headers MUST compile when included alone and MUST NOT leak unnecessary heavy dependencies.
- Use conventional include guards or `#pragma once` consistently within a project; prefer guards for maximally portable C public headers.
- Public headers MUST document transfer ownership, nullable parameters, callback lifetimes, thread requirements, and error contracts.
- Hide internal symbols with `static` or appropriate visibility controls.

### 5.2 GObject and GLib conventions

- Use standard `G_DEFINE_TYPE`, `G_DECLARE_FINAL_TYPE`, and related macros where applicable.
- Pair `ref`/`unref`, allocations/frees, signal connections/disconnections, and callback lifetimes.
- Prefer `g_autoptr`, `g_autofree`, and `g_clear_*` where supported and appropriate; avoid mixed cleanup conventions in one routine.
- Use `GError **` correctly. On success, do not set an error. On failure, use a stable `GQuark` domain and code; do not return partially valid objects without documenting that possibility.
- Check external lengths, counts, offsets, record sizes, and integer arithmetic before allocations or pointer access.
- Do not log and then suppress an error when the caller must decide how to recover.
- GObject signals, properties, and introspection annotations are public contracts; do not rename or reorder enum values casually.

### 5.3 Example: checked operation

```c
static gboolean
calculate_buffer_size (size_t count,
                       size_t element_size,
                       size_t *total_bytes,
                       GError **error)
{
    g_return_val_if_fail (total_bytes != NULL, FALSE);

    if (element_size != 0 && count > SIZE_MAX / element_size) {
        g_set_error_literal (error,
                             G_IO_ERROR,
                             G_IO_ERROR_INVALID_ARGUMENT,
                             "Requested buffer size overflows size_t");
        return FALSE;
    }

    *total_bytes = count * element_size;
    return TRUE;
}
```

Use the actual domain/error code appropriate to the project; the example illustrates validation structure, not a mandated universal error mapping.

---

## 6. C++ (C++17 or project-declared minimum)

### 6.1 Includes and class ordering

Use own header first, then standard C++ headers, C system headers if needed, third-party headers, and project headers. Sort alphabetically within each group, with blank lines between groups.

A class declaration SHOULD follow:

1. Public types and constants.
2. Public constructors/destructor and explicitly intended special members.
3. Public methods and queries.
4. Protected interface, if needed.
5. Private helpers.
6. Private fields grouped by lifetime/responsibility.

In `.cpp`, group implementations by constructors/lifecycle, public operations, and private helpers. Match header declarations and definitions consistently.

### 6.2 Ownership, errors, and interop

- Prefer RAII and `std::unique_ptr`/`std::vector` to manual `new`/`delete` and raw owning pointers.
- Use `std::span` only when the project's C++ minimum permits it; for C++17 use explicit pointer+length or appropriate views.
- Make non-owning pointers and references clearly non-owning.
- Explicitly delete or implement copy/move operations when resource ownership requires it.
- Use `noexcept` only when the promise is reliable.
- Handle exceptions **inside** a C ABI boundary. Never allow C++ exceptions to escape a GLib/C/Vala callback or exported C function.
- Convert failures into the owning layer's documented error representation without losing diagnostic context.
- Check arithmetic for buffer sizes and index calculations.
- Avoid holding borrowed `char *` pointers beyond the originating object's lifetime.

```cpp
extern "C" bool
process_request (const char *path, ErrorInfo *error) noexcept
{
    try {
        return process_request_impl(path);
    } catch (const std::exception &exception) {
        set_error(error, exception.what());
        return false;
    } catch (...) {
        set_error(error, "Unknown request processing failure");
        return false;
    }
}
```

The exception wrapper illustrates the boundary; the actual `ErrorInfo` type and helper are project-defined.

### 6.3 Optimization discipline

Avoid accidental deep copies of large buffers; use moves and references where ownership permits. Measure memory allocation patterns and time spent in conversions before replacing clear abstractions with lower-level code. Preserve exact observable results or documented numerical tolerances.

---

## 7. Vala / GTK4 / libadwaita

### 7.1 File layout and imports

Use necessary `using` directives at the top of the file, sorted consistently and separated from the namespace or class. Avoid wildcard-like dependence on imports that introduce ambiguous symbols. Keep one primary responsibility per file, not necessarily one class per file.

Preferred Vala class ordering:

1. Documentation and class declaration.
2. Constants, enums, nested/private types.
3. Signals and public properties.
4. Private backing fields, grouped by responsibility.
5. Construction, template initialization, event-controller setup.
6. Public operations, then public read/query methods.
7. Private operations grouped by feature (loading, interaction, rendering, playback).
8. Cancellation, disconnect, dispose/cleanup routines adjacent to related lifecycle logic.

Exact language-mandated ordering and clarity take precedence over strict numeric ordering.

### 7.2 Ownership and asynchronous work

- Understand Vala `owned`, `unowned`, `weak`, `ref`, and nullable semantics; do not force one ownership qualifier everywhere.
- Avoid reference cycles caused by signals, closures, widgets, or long-lived services.
- Track and disconnect signals when the source can outlive the consumer.
- Use `GLib.Cancellable` for I/O and costly asynchronous operations that support cancellation.
- Separate **user cancellation**, **superseded request**, **temporary unmap/suspension**, and **disposal**.
- Generation/request tokens MUST prevent older callbacks from overwriting newer state.
- Never block the GTK main loop with heavy computation, remote I/O, process waits, database queries, or other expensive synchronous work.
- Thread-affine GTK object updates MUST occur on the correct main context.
- Avoid global mutable widget state; multiple instances must be independent.

### 7.3 UI and styling

- GTK4 and libadwaita interfaces SHOULD use `.ui` XML templates for declarative controls, layout, properties, and signal wiring.
- XML cannot replace imperative rendering code, gesture handling, or other runtime behavior; keep those in Vala/C as needed.
- Respect Majoris Theme for colors, spacing, borders, shadows, focus styling, and common widget appearance. **Do not hardcode application-specific CSS** unless the reusable theme does not provide a required semantic style, and then document the exception.
- Do not embed application-specific headers/toolbars/dialogs inside reusable, neutral widgets.
- Give custom interactive widgets appropriate accessibility roles, names/descriptions, keyboard access, and state reporting.
- Keep domain logic, data access, and presentation separated at sensible boundaries.

### 7.4 Example: cancellation-safe async update

```vala
private uint request_generation = 0;
private Cancellable? active_request;

public async void refresh_items () throws Error {
    active_request?.cancel ();
    var request = new Cancellable ();
    active_request = request;
    uint generation = ++request_generation;

    var items = yield repository.list_items (request);
    if (request.is_cancelled () || generation != request_generation) {
        return;
    }

    current_items = items;
    notify_property ("item-count");
}
```

This is an illustrative pattern, not drop-in code: production methods must also account for errors, disposal, ownership, and expected cancellation semantics.

### 7.5 Vala local type inference (`var`) — Majoris policy

**Default:** for new or intentionally standardized Vala code, **MUST prefer `var` for a local variable immediately initialized by an expression whose exact inferred static type is clear and correct**. This is Majoris style policy, not a rule that upstream Vala requires `var`. The official Vala manual explicitly supports inference for local declarations with initializers; the inferred type is fixed at compile time, just as with an explicitly typed local. This is C#-like syntax, **not** C# runtime or memory management.

#### 7.5.1 Language facts (upstream) versus organization preference

- Vala allows `var identifier = expression;` **for local declarations** when the initializer unambiguously determines a type; an uninitialized `var` declaration is not supported. The inferred type is the initializer's type; a later assignment does not change it.
- Vala is statically typed; `var` is **not** `dynamic`, an object root type, a runtime variant, or permission to assign an unrelated class later.
- `foreach (var item in collection)` is a supported, idiomatic form when the element type is clear (subject to the supported compiler and collection type).
- Ordinary fields, signals, properties, public/private method parameters, return signatures, interface members, delegate signatures, and exported ABI definitions **MUST retain explicit types**. Do not assume C#'s type-inference facilities or syntax beyond what the targeted `valac` version supports.
- Vala owns, borrows, copies, and releases references according to **Vala ownership semantics**. `var` does not eliminate reference counting, copying, string duplication, or memory allocation. An explicit `owned`, `unowned`, or `weak` qualifier is required whenever the lifetime contract must be expressed; prefer the explicit type if it avoids ownership ambiguity.
- A type chosen by inference may differ from the deliberate base interface, nullable type, numeric width, or conversion type the author intended. **Preserving semantics overrides `var` preference.**

Official references: https://gnome.pages.gitlab.gnome.org/vala/manual/statements.html (Variable declaration); https://gnome.pages.gitlab.gnome.org/vala/manual/concepts.html (Local variables/ownership); https://docs.vala.dev/guides/compiler-guide/02-00-environment-setup.html (Vala compiler code style); https://docs.vala.dev/guides/memory-management.html (owned/unowned/weak).

#### 7.5.2 Decision table — normative

| Declaration context | Majoris requirement | Reason |
|---|---|---|
| Local from `new ConcreteType (...)` | **Prefer `var`** when concrete type is intended | Type is already spelled in initializer |
| Local from method returning a clear static type | **Prefer `var`** | Avoid needless repetition |
| `foreach` over typed collection | **Prefer `var`** when safe and clear | Element type is inferred |
| Local from `yield operation_async (...)` | **Prefer `var`** if result, ownership, and nullability are correct | Async does not prevent inference |
| Local initialized with a property/getter | **Prefer `var`** only if intended static type and lifetime are clear | Avoid hidden interface/ownership changes |
| Local initially `null` / assigned later | **Explicit nullable or ordinary type required** | No useful initializer to infer |
| Local intentionally widened to interface/base class | **Explicit interface/base type required** unless a tested explicit cast communicates intent | Concrete `var` type can change overload/dispatch |
| Byte/offset/count/bitmask/precision-sensitive numeric variable | **Explicit numeric type SHOULD be used** when width, signedness or precision matters | `var x = 0` infers `int`, not arbitrary-width count |
| Literal expression with ambiguous numeric or collection type | **Explicit type required** (or a safe intentional cast) | Avoid unwanted conversion or overload resolution |
| Borrowed reference/pointer, nontrivial ownership boundary | **Explicit `unowned`/`weak`/`owned` contract and usually explicit type** | Correct lifetime matters more than brevity |
| Pointer/array/generic/nullable type not inferred as intended | **Explicit type required** | ABI, ownership and generated-C behavior may differ |
| Local whose concrete inferred type is intentionally significant | `var` permitted; explicit type MAY be retained when it documents a subtle contract | Clarity takes precedence |
| Instance/static field, property, signal, method signature, delegate, C interop declaration | **Explicit type required** | Stable interface and discoverability |
| Global/public API, GIR/VAPI, protocol/serialization definition | **Explicit type required** | Compatibility contract |

**Examples (illustrative):**

```vala
// Prefer when the initializer communicates the exact desired local type.
var request = new Cancellable ();
var names = new Gee.ArrayList<string> ();
var record = yield repository.load_async (request);
foreach (var name in names) {
    process_name (name);
}

// Preserve intentional types and boundaries.
Record? selected = null;                 // Nullable and assigned later.
uint64 total_bytes = 0;                  // Width-sensitive counter.
TaskExecutor executor = new LocalExecutor (); // Interface intentionally selected.

// Borrowed reference: explicit lifetime contract is more important than var.
unowned string borrowed_name = record.get_name ();
```

The example assumes `repository.load_async()` returns a type that supports the shown `get_name()` access, and that `get_name()` returns an appropriate borrowed reference. In production, inspect the **actual VAPI signature and lifetime** before using `unowned`; do not cargo-cult qualifiers or replace an owned getter with a borrowed one.

**Avoid:**

```vala
var missing = null;            // No unambiguous intended type.
var bytes = 0;                 // Wrong if a uint64/size_t byte counter is required.
var executor = new LocalExecutor (); // Wrong when code needs TaskExecutor's abstraction.
```

`var executor = new LocalExecutor ();` is valid Vala, but inappropriate **when the intended declared contract is `TaskExecutor`**. This is a policy/semantic warning, not a claim that the syntax is invalid. Likewise, an explicit `Record? selected = null;` is not stylistic inconsistency—it is intentional type information.

#### 7.5.3 Conversion review (existing Vala files)

A local declaration conversion such as `ConcreteType value = create ();` to `var value = create ();` is allowed only if all of the following hold:

1. The new inferred compile-time type is the **same intended type**, not an unintended subtype, base type, boxed value, pointer, nullable/non-nullable type, or numeric width.
2. Ownership/ref-count/copy/borrow behavior is preserved; inspect generated C where native/compact ownership makes this non-obvious.
3. Overload resolution, signals, property bindings, generics, nullability checks and casts remain correct.
4. No public ABI, GIR/VAPI, GObject property/signal contract, worker serialization, or error code changes.
5. The diff remains limited to declaration style; formatting-only conversions are separate from behavioral refactors.
6. The project compiles under its **minimum supported** `valac` version and passes tests; for hot paths, compare generated C or benchmarks where a type difference could affect output or performance.

Do not bulk replace explicit locals using regular expressions. An automated tool may propose changes, but a language-aware review MUST approve each declaration. A field or public signature MUST NEVER be rewritten to `var` to increase its usage percentage. Do not use a numeric "percentage of var" compliance target.

#### 7.5.4 Practical consistency rule

For code review, ask **"Can the exact intended type be read from this initializer without affecting ownership, numeric behavior or an interface boundary?"** If yes, use `var`. If not, write the type explicitly and, where useful, document the invariant. This is a consistent convention, not a requirement to make every declaration visually identical.


---

## 8. Python tooling and tests

### 8.1 File and import order

Use `#!/usr/bin/env python3` only for scripts that execute directly. At the top: license/header if needed, module docstring, `from __future__` imports, standard-library imports, third-party imports, project imports, constants, helpers, `main()`, entry-point guard.

```python
"""Validate configuration fixtures."""

import argparse
import json
from pathlib import Path

DEFAULT_TIMEOUT_SECONDS = 30


def inspect_fixture(path: Path) -> None:
    """Verify that a fixture contains a valid JSON object."""
    with path.open(encoding="utf-8") as source:
        data = json.load(source)
    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    inspect_fixture(args.path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Real project files MUST remove unused imports and dependencies.

### 8.2 Conventions

- Use PEP 8, Ruff formatting and linting, meaningful `argparse` interfaces, and a `main()` returning an exit code for executable tools.
- Follow §4.1.1–§4.1.3 for readable multiline suites and spacing; retain PEP 8's two blank lines between top-level definitions and one between methods. Do not compress `if`, `try`, `except`, or loops into one-line suites.
- Use `pathlib.Path` for filesystem paths; avoid fragile manual string concatenation.
- Use `subprocess.run([...], check=True, timeout=..., text=True)` for ordinary bounded subprocess calls. Avoid `shell=True` for untrusted arguments.
- Give subprocesses defined timeouts and ensure cleanup on failure.
- Use `tempfile.TemporaryDirectory()` or pytest temporary directories for temporary state.
- Provide precise failure messages and nonzero exit codes for broken tooling.
- Prefer deterministic fixture generation, seeded randomness, and explicit input/schema/version assumptions.
- Add type hints to new nontrivial helpers; do not introduce unnecessary packaging frameworks for a handful of internal scripts.
- Never modify checked-in binary fixtures silently as a side effect of tests.

### 8.3 Docstrings

All handwritten Python modules, classes and functions MUST have meaningful PEP 257 docstrings, including private helpers and test utilities; see §15.2.4. Explain arguments, results, errors and side effects when relevant. Use American English.

### 8.4 Python test runners and helper modules

- Prefer Python for **test orchestration**, not as a mandatory replacement for the language under test. Native C/C++ tests and Vala/GLib/GTK tests SHOULD exercise the corresponding APIs directly. See §17.6.
- A test runner's `main()` SHOULD parse and validate arguments, then delegate distinct operations to small testable functions. Keep modules import-safe; never start subprocesses or mutate fixtures on import.
- Use `subprocess.run()` for bounded single-process operations and `subprocess.Popen()`/process groups only when concurrency or explicit lifecycle management is required. Preserve subprocess return codes and relevant stdout/stderr; do not convert failed assertions to warnings.
- Use `tempfile`/pytest fixtures to isolate mutable state. When coordinating several processes, explicitly own, await, terminate, and reap them on every exit path. Use `pathlib.Path` and argument arrays, never untrusted shell concatenation.
- Use standard `unittest`, pytest, or GLib test assertions as appropriate; avoid creating a custom framework just for uniformity. Type hints, reusable fixtures, and descriptive diagnostics SHOULD be proportional to complexity.

---

## 9. Meson build system

### 9.1 Design principles

- Meson is the authoritative description of build dependencies and targets; do not duplicate major dependency logic in shell scripts.
- Keep `if`/`else`/`endif` and `foreach`/`endforeach` bodies on separate lines; avoid compressed one-line control flow or multiple unrelated statements crammed into one line. Use one blank line between logical phases, not repeated empty lines.
- Make optional dependencies explicit with Meson `feature` options (`enabled`, `disabled`, `auto`) where appropriate.
- Use `dependency(..., required: get_option('feature'))` or equivalent supported patterns; do not silently enable features that packagers intended to disable.
- Keep source trees clean; generated headers, VAPI, GIR/typelibs, and code belong in the build tree until installed.
- Build and source paths MUST be portable and not depend on a developer-specific directory.
- Respect `prefix`, `libdir`, `datadir`, and architecture-specific installation variables.
- Do not call out to `apt`, `sudo`, or network downloads as part of normal `meson setup` or compilation.
- Avoid environment-dependent feature behavior in release packages unless the dependency policy explicitly documents it.

### 9.2 Root `meson.build` ordering

Use this conceptual order:

1. `project()` and global language standards.
2. Meson modules/imports and global configuration.
3. Compilers/toolchain detection.
4. Required dependencies.
5. Optional feature options and dependency checks.
6. Generated configuration headers and feature summaries.
7. `subdir()` calls in **dependency order** (native before core if core links to native; core before GTK if GTK links to core; tests after targets).
8. Project summary and packaging-oriented metadata, if applicable.

Avoid scattering repeated `dependency()` calls across unrelated subdirectories when the dependency can be resolved once and passed coherently.

### 9.3 Per-directory `meson.build` ordering

1. Local dependencies/feature conditions.
2. Compiler/link arguments and generated configuration.
3. Source lists (logical groups; alphabetized **within** groups).
4. `static_library()`, `shared_library()`, `executable()`, or `custom_target()` declarations.
5. `declare_dependency()` for consumers and public interfaces.
6. Header, VAPI, GIR, GResource and data installation.
7. Test registrations specific to this component, or defer to `tests/`.

Comments should explain **why** a condition/target exists, not restate the Meson instruction.

### 9.4 Example (illustrative)

The example assumes the shown source subdirectories exist and the following options are declared in `meson.options`:

```meson
option('gtk', type: 'feature', value: 'auto', description: 'Build GTK user interfaces')
option('secret_storage', type: 'feature', value: 'auto', description: 'Use the system credential store')
```

```meson
project(
  'example-service',
  ['c', 'vala'],
  version: '2.0.0',
  default_options: ['c_std=gnu11', 'warning_level=2'],
)

glib_dep = dependency('glib-2.0', version: '>=2.74')
gio_dep = dependency('gio-2.0')

# Optional integrations use their corresponding feature options.
secret_dep = dependency('libsecret-1', required: get_option('secret_storage'))
gtk_dep = dependency('gtk4', required: get_option('gtk'))

subdir('src/core')

if gtk_dep.found()
  subdir('src/gtk')
endif

subdir('tests')
```

Use the actual minimum dependency versions and options for the repository. For a feature option defaulting to `auto`, test the discovered dependency with `.found()` rather than only checking whether the option is explicitly enabled before building dependent targets. Declare `secret_dep` to the targets that need it, rather than linking it to unrelated components.

### 9.5 Source list and target naming

Prefer explicit, reviewable source lists for library targets over broad globbing. Place related files next to each other and sort inside those groups. Use descriptive `*_sources`, `*_deps`, `*_include_dirs`, and `*_lib` variable names, not `a`, `files1`, or `deps2`.

Separate public dependencies from internal implementation dependencies. Expose only what consumers require through `declare_dependency()` and pkg-config.

### 9.6 Testing, warning levels, and reproducibility

- Use `meson test --print-errorlogs` routinely.
- Group tests into suites such as `unit`, `integration`, `slow`, `installed`, `security`, and `performance` where appropriate.
- Keep a fast deterministic default test suite. Register expensive extended tests separately; do not leave them reachable only through undocumented manual flags.
- Give tests independent cache/config/tmp directories. Do not make tests depend on a developer's real home directory.
- Increase warning diagnostics in CI (`warning_level=2` or `3` after stabilization); use `werror=true` where the toolchain and dependencies allow it without hiding legitimate cross-version concerns.
- Validate optional-feature combinations relevant to the repository, including GUI/headless mode, offline mode, optional integrations enabled/disabled, and GIR/VAPI generation where used.
- Test **installed consumers**, not only in-tree targets.
- When using code generation, pin and document minimum supported tool versions, and avoid depending on features newer than the target Debian distribution.

### 9.7 Test-directory Meson organization

- A large `tests/meson.build` SHOULD delegate **cohesive groups** to `tests/unit/meson.build`, `tests/integration/meson.build`, `tests/security/meson.build`, etc., when the separation makes targets and conditions easier to follow. Small projects MAY retain a single test file; do not create empty subdirectories.
- The top-level `tests/meson.build` SHOULD coordinate shared fixture generation, common environment construction, and `subdir()` calls in **dependency order**. Each child Meson file SHOULD declare the targets and tests it owns; use concise comments for non-obvious build constraints.
- Use explicitly declared source lists and explicit dependencies for generated fixtures. Do not rely on test order, current working directory, or source-tree writes. When `subdir()` changes `meson.current_build_dir()`, update references deliberately; preserve externally consumed generated artifacts or migrate all consumers atomically.
- **Physical location and Meson suite are independent.** A test in `integration/` may be registered in an `extended`, `security`, or `platform` suite when appropriate. Preserve existing test names, options, feature guards, timeouts, prerequisites, and skip semantics during file moves.
- Move executable helpers, fixture producers, benchmarks, and release checks with their own related code; do not put production entry points into reusable test libraries. Use stable absolute or declared file paths instead of fragile `../` assumptions.
- Do not duplicate dependency detection in every test directory. Define shared dependencies once where practical and expose clear, deliberately named Meson variables; Meson `subdir()` processing shares configuration state, so avoid accidental variable shadowing.
- Test source builds and installed-consumer builds separately. CI and qualification scripts MUST invoke the real registered Meson targets rather than assume that a file move cannot affect the build graph.

---

## 10. Debian packaging and installed interfaces

### 10.1 General rules

- Debian packages MUST follow the actual runtime SONAME and Debian policy for shared libraries.
- When SONAME changes incompatibly, review ABI-specific runtime package naming and upgrade/co-install relationships.
- Development packages SHOULD include headers, unversioned `.so` link symlinks, VAPI, pkg-config and GIR files appropriate to the library.
- Runtime packages MUST include required workers, runtime dependencies, and correct installed paths without bundling unnecessary development files.
- Verify `Depends`, `Breaks`, `Replaces`, `Provides`, `Multi-Arch`, symbols/shlibs, and packaging of optional features.
- Avoid invalid placeholder maintainer contacts in publicly released packages.
- Use Debian debhelper/Meson integration rather than duplicating install logic in ad hoc shell scripts.
- Keep Debian `debian/rules` executable and verify Git/source archive modes. Make maintainer scripts idempotent, quiet, failure-aware, and safe during upgrades/removal.
- Never require network access, `sudo`, or manual host modification as part of package builds.

### 10.2 Versioning and ABI

Maintain distinct concepts:

- **Product version:** human-facing release number.
- **Public API version:** contract for callers and generated development interfaces.
- **SONAME/ABI:** binary compatibility for linked consumers.
- **Debian package version:** packaging and distribution revision.

These values may differ. Never rename public namespace/GType/C symbols or change enum numeric values in an allegedly behavior-neutral cleanup without an explicit migration.

### 10.3 Release verification

Build in a clean Debian 13 environment, run Lintian, inspect package contents and ELF dependencies, install and remove/reinstall packages, compile an external C/Vala consumer, validate GTK XML instantiation, and check worker/resource paths. Report nonstandard runtime requirements and available/unavailable optional dependency profiles.

---

## 11. Public API, ABI, GObject, and data compatibility

Treat these as externally observable and versioned:

- Exported C functions, structs, enums, shared symbols, SONAMEs.
- Vala namespaces, methods, properties, signals, ownership annotations, VAPI filenames.
- GObject GType names, GObject property/signal names, GtkBuilder class strings.
- GIR namespaces and type descriptions.
- D-Bus object paths, methods, interfaces, services.
- GSettings schemas and keys, environment variables, CLI options.
- Worker requests/responses, stored cache formats, JSON/XML keys, on-disk databases.
- `.desktop` IDs, MIME IDs, D-Bus activation names, installed executable names.

Changes require a compatibility inventory, migration/alias strategy if appropriate, ABI analysis, tests of old consumers and old data, and a documented release decision. Internal refactoring MUST NOT change any of these inadvertently.

For shared flags across C/Vala, use an authoritative declaration or a generated/common constant definition plus build-time agreement checks. Never duplicate magic numeric capability masks in multiple languages.

---

## 12. Errors, logging, and diagnostics

- Return meaningful typed errors rather than `false`/`null` with no explanation when a caller needs diagnosis.
- Separate invalid input, unsupported capability, canceled operation, timeout, resource exhaustion, dependency unavailable, and unexpected implementation failure.
- Do not transform an expected cancellation into a user-visible error.
- Use stable library-level error domains; avoid obsolete application names in shared-library errors.
- Logs SHOULD contain enough context to diagnose a failure without exposing secrets, full private file contents, or unnecessary identifying data.
- Use one logging convention per subsystem (`g_debug`, `g_warning`, structured logging, etc.) with clear severity distinctions.
- Avoid noisy per-item/per-request logging on normal hot paths. Add optional targeted diagnostics instead.
- Do not swallow exceptions silently; when intentionally ignored, state why and what fallback is used.
- Do not report external hardware/platform behavior as verified when only source-level or simulated conditions have been tested.

---

## 13. Memory, ownership, cancellation, and concurrency

### 13.1 Common resource contract

For each resource (file, FD, buffer, GObject, database handle, subprocess, temp dir, timer, signal handler, native handle), state who owns it, how ownership transfers, when it is released, and which thread/context may access it.

- Prefer scoped ownership and cleanup on all paths.
- Bound caches and work queues in bytes and/or count, with clear eviction rules.
- Avoid retaining complete datasets or duplicate buffers when bounded or incremental processing is sufficient.
- Do not assume canceled tasks stop instantly; stale results MUST be prevented from publishing.
- Avoid holding locks across expensive computation, blocking I/O, callback invocation, or signal emission.
- Distinguish instance-local mutable state from shared immutable caches or services.
- Use synchronization based on actual ownership and access patterns; avoid unnecessary global locks.
- Establish a scheduler priority contract using named priorities; foreground requests should not be starved by background work.

### 13.2 Atomic file/cache operations

For shared caches and worker artifacts:

1. Validate source identity and resource limits.
2. Use unique private temporary files.
3. Write a complete result; validate it if necessary.
4. Publish atomically on the appropriate filesystem.
5. Coordinate concurrent writers where appropriate.
6. Clean up after cancellation/crash and verify cache validity on read.

Do not confuse structural metadata validation (such as headers, lengths, or checksums) with full semantic validation when correctness requires parsing or processing the contents.

---

## 14. Security and untrusted input

All files received from users, network shares, archives, other applications, and removable devices are untrusted unless proven otherwise.

- Validate lengths, counts, offsets, integer products, protocol fields, record sizes, nesting depth, and decompression ratios before allocating or indexing.
- Keep parsers and risky native processing inside the existing sandbox/worker process when architecture requires it.
- Use read-only mounts and least-privilege file access where possible; avoid silently falling back to unsafe in-process handling.
- Preserve CPU, memory, file-size, request-count, runtime, FD, and output-size limits.
- Never use shell interpolation with untrusted file paths.
- Handle malformed UTF-8, partial I/O, truncated files, noncanonical paths, symlinks, remote paths, and interrupted processes.
- Test worker crashes/timeouts, cleanup, and cache corruption independently.
- Fuzz custom parsers and protocol handlers, and use ASan/UBSan in native-code CI where compatible.
- Keep dependency versions updated for security, but do not introduce undocumented binary/vendor requirements.
- Document security-sensitive invariants in nearby comments and targeted tests.

---

## 15. Comments, documentation, and source readability

### 15.1 Comment intent

Comments should explain **why**, **assumptions**, **invariants**, **limitations**, and **non-obvious contracts**, not narrate obvious statements.

Good:

```c
/* A canceled operation may still complete asynchronously. The generation
 * check prevents its result from replacing the latest requested state.
 */
```

Unhelpful:

```c
/* Increment count. */
count++;
```

### 15.2 Declaration-level documentation (mandatory)

**Requirement:** Every project-owned **handwritten** class, interface, struct, enum, error domain, delegate, constructor, method/function, property and public signal MUST have a meaningful declaration-adjacent, tool-recognized description, regardless of public, internal, protected or private visibility. This is the cross-project equivalent of a C# `/// <summary>` contract; use the **native language documentation syntax**, not C# XML tags. Meaningful exported fields and non-obvious private ownership/invariant fields MUST be described. Enum values SHOULD be described individually where their meaning is not self-evident or they encode protocol, state or policy.

A valid declaration comment MUST explain **what the symbol represents, produces, controls, or guarantees**, not simply expand its spelling. Describe units, default values, ranges, nullability, ownership, threading/main-context, error conditions, cancellation, security or external side effects where those details affect callers or maintenance. A one-sentence description suffices for an obvious private helper; elaborate contracts need several sentences. Do not manufacture filler to hit a numerical coverage target or annotate every obvious statement inside a method.

**Existing-source migration:** Perform a repository-wide source documentation pass once, in a documentation-only commit or isolated patch series, prioritizing public API and security-sensitive contracts. New and touched declarations MUST be compliant immediately. Exclude generated, vendored and upstream files, non-code fixtures, compiler-generated declarations and third-party compatibility headers. Document intentional omissions narrowly. Do not create new classes or split files solely to make a coverage metric easier.

#### 15.2.1 Vala / GObject (Valadoc)

- Put a `/** ... */` Valadoc comment immediately before every type, class member, constructor, method, public property and signal. Place comments **before** `[CCode]`/other annotations when the attribute forms part of the declaration, and keep annotations attached to their original declarations.
- Class/interface documentation states responsibility and supported invariants; method documentation states effect, returned value and notable errors/cancellation; property documentation states domain meaning, units, defaults, writable/read-only behavior or ownership when non-obvious. Explain special page/frame, source/sample precision, crop, exposure, zoom and time units in owning repositories where applicable.
- Existing method signatures, GObject type names, enums, properties, signals, GIR/VAPI symbols, ownership qualifiers and async semantics MUST NOT change to satisfy documentation. Do not introduce unsupported tags or annotations; prefer valid Valadoc prose and confirmed parameter-reference conventions.
- Private helper documentation may be brief but MUST identify its particular contract or invariant. Do not repeat `Gets foo` for a property whose essential semantics are not self-evident.

Illustrative example:

```vala
/** Contains the results of loading a single record. */
public sealed class RecordResult : Object {
    /** Time since the Unix epoch in microseconds; zero means unknown. */
    public int64 timestamp_us { get; private set; }

    /**
     * Loads a record without blocking the calling main context.
     *
     * Cancellation leaves the existing result unchanged. The caller owns
     * the returned object. Errors are propagated to the caller.
     */
    public async Record load (string key, Cancellable? cancel = null) throws Error {
        // Implementation.
    }
}
```

#### 15.2.2 C / GLib / GObject (gtk-doc / gi-docgen)

- Document each handwritten public declaration in its owning header using gtk-doc-compatible `/** symbol_name: ... */`, accurate `@argument` descriptions, `Returns:` where applicable, and introspection annotations **only when supported and correct**. Internal/private functions and structs MUST also have structured descriptions at their declarations/definitions; a standard Doxygen block is acceptable for internal functions not exposed to GIR.
- Pointer returns and pointer arguments should document transfer ownership, nullability and lifetime when applicable. Async/finish pairs MUST explain callback lifetime and ownership transfer, error rules and whether NULL is successful. C ABI documentation must not alter function signatures or introspection annotations without separate compatibility review.

```c
/**
 * record_store_open:
 * @path: Filesystem location of the store.
 * @error: (out) (optional): Error information on failure.
 *
 * Opens an existing store without creating missing files.
 *
 * Returns: (transfer full) (nullable): An owned store or NULL on failure.
 */
RecordStore *record_store_open(const char *path, GError **error);
```

#### 15.2.3 C++ (Doxygen)

- Use a consistent `/** ... */` or `///` Doxygen-compatible comment on every handwritten class, constructor, method and relevant field, including private helpers. Explain resource lifetime, exception translation at C ABI boundaries, side effects, threading, and unsafe/pointer invariants where relevant.
- Do not claim a C++ function is noexcept, thread-safe or ownership-transferring unless its implementation actually guarantees that behavior.

#### 15.2.4 Python (PEP 257)

- Every handwritten Python module, class, function, method and property getter MUST have a docstring as its first statement; prefer triple-double quotes. Document what the callable does and the important inputs, result, exceptions, file/process/network effects, fixture invariants or CLI exit status. Keep parameter descriptions proportional to the complexity of the operation.
- Use documented decorators/descriptor conventions instead of duplicating identical docstrings on simple setters. Preserve public function signatures and return values; the `__doc__` metadata change from adding docstrings is intentional.

#### 15.2.5 Coverage verification and quality gates

- Repositories MUST maintain a reproducible **source documentation coverage** checker or equivalent CI rule that recognizes the project's declared languages and skips generated/vendor outputs. The checker SHOULD show totals and uncovered declarations by file/type/visibility and fail new contributions missing required summaries.
- For Vala, use a language-aware declaration scan and validate with the supported `valac`/Valadoc toolchain when available. For Python, use the `ast` module to locate docstrings reliably. For C/C++, prefer a parser/compilation database or match source declarations conservatively and review exceptions. An automatically generated summary that repeats the identifier without conveying meaning is **not compliant** even if a parser counts it.
- The documentation migration MUST pass compilation and appropriate existing tests and ABI/GIR/VAPI/installed-consumer checks before release. No changes to logic, public naming, serialized values, exported symbols, library dependencies, worker protocol or resource limits may be bundled into a documentation-only patch.
- Do not claim toolchain-dependent validation passed if it was not run. Compare existing source code after ignoring only inserted documentation comments and Python docstrings to detect inadvertent code changes. Separate optional formatting-only changes from the documentation migration.

### 15.3 Workarounds and TODOs

Workarounds MUST say which upstream version/bug/constraint caused them and what condition permits removal. TODOs SHOULD identify a concrete task and, where available, an issue link. Do not litter completed code with stale TODOs, commented-out alternate implementations, or fake success paths.

### 15.4 Markdown and architecture docs

Use informative headings, short paragraphs, fenced code blocks with language tags, consistent terms, and examples that actually compile against the supported public API. Separate confirmed behavior from platform limitations and optional dependencies.

---

### 15.5 Repository README standard (mandatory)

Every Majoris repository **MUST** provide a root `README.md` written in
American English. The README is the **current, public entry point** for
installers, developers, integrators, and reviewers. It MUST explain what the
project actually provides, how to obtain and build it, and where the
versioned, authoritative contracts live. It is not a historical audit log, a
marketing promise, or a dump of every implementation detail.

#### 15.5.1 Canonical order and heading names

Use the following preferred top-level order; retain the headings that apply
and omit or explicitly mark non-applicable sections rather than creating
empty placeholders. Repositories MAY adjust wording where their domain
requires it, but MUST retain the same information in a discoverable location:

1. **Project name** (`# Product Name`) — one accurate, clear description.
2. **Project metadata** — version, intended platform, maturity/status, license
   and public API/ABI when applicable; do not substitute the application version
   for SONAME or protocol version.
3. **Contents** — a linkable table of contents for nontrivial README files.
4. **Features** — user/consumer-facing capabilities and important limitations.
5. **Supported formats / integrations / platforms** — domain-specific support
   matrix when applicable; for libraries processing files or media, this section
   is mandatory. For other projects, substitute relevant backends or protocols.
6. **Requirements and dependencies** — minimum supported platform, toolchain,
   runtimes, optional components and authoritative package manifest.
7. **Building and installing** — copyable commands, build options, headless or
   optional configurations, installation and packaging where provided.
8. **Quick start / usage** — working minimal examples for principal workflows.
9. **Public API reference** — mandatory for public libraries and developer
   SDKs; summarize the public surfaces and link to the detailed versioned API.
   For apps/services/CLIs, document CLI commands, D-Bus interfaces, service
   endpoints, user interactions or supported plugin contracts as applicable.
10. **Architecture and source layout** — concise subsystem and dependency map,
    with a link to a detailed architecture record if the project needs one.
11. **Security, resources and compatibility** — trust boundaries, data
    handling, permissions, runtime requirements, versioned interfaces,
    migration considerations and material limitations.
12. **Testing and release qualification** — actual test commands, additional
    profiles, fixture and hardware requirements, plus qualification caveats.
13. **Documentation and contribution** — links to existing guides, standards,
    examples, design decisions and contribution instructions.
14. **License** — SPDX expression or license identification, local license
    files, and material third-party or asset provenance.

For a small single-purpose tool, a concise README that visibly covers each
applicable concern is preferable to 14 empty sections. For a large reusable
library, the API, supported-format and build sections are not optional.

#### 15.5.2 Features, support claims, and accuracy

- A README **MUST describe implemented behavior**, not future design goals,
  unresolved tasks, or features known only from a marketing description.
- State whether format, codec, protocol, hardware, database, integration or
  platform support is **built in**, **optional**, **runtime-discovered**, or
  **experimental/unverified**. Do not collapse all into a blanket “supported.”
- For media or file-processing projects, format tables SHOULD distinguish
  decode/read, encode/write, animation/multipage, precision/color handling,
  important restrictions and conditional dependencies. A detailed matrix MAY
  live in an owned `docs/` file if the README gives a truthful summary and
  links directly to it.
- Document the actual supported baseline and minimum version; avoid assuming
  every available dependency plugin or driver is installed.
- Distinguish file/metadata capability from hardware display/output
  qualification. Do not describe a simulated test as physical hardware proof.
- Separate **current release status** from historical benchmarks and reports.
  A source archive's included test report MUST NOT imply the modified archive
  was subsequently tested unless it actually was.

#### 15.5.3 Public API and examples

For a public library or SDK, the README **MUST** document:

- Versioned namespaces/package names, shared-library/SONAME or module names,
  installed public headers/VAPI/GIR, and the appropriate import syntax.
- Public entry-point types and methods **by responsibility**, including the
  principal parameters, asynchronous or error contract, and output type when
  important to safe use. A readable method index plus a link to a more
  exhaustive versioned API is acceptable; do not present a private helper as
  public or claim undocumented signatures.
- Consumer object lifetimes, transfer semantics, thread/main-context
  affinity, cancellation and resource limits where they materially affect use.
- One minimal copyable example per primary consumer workflow, consistent with
  the current installed API and the supported minimum language version.
- Public signals/properties, schema keys, CLI flags and extension points as
  relevant. Do not rename existing public interfaces while changing README
  terminology; cross-check with headers, VAPI, GIR, CLI help or API tests.
- A pointer to API migration and ABI compatibility notes if different major
  versions coexist or old consumers require coordinated upgrades.

For applications, services and CLIs, replace the library API index with the
appropriate stable user-facing and machine-facing interface documentation.
Do not invent a public API section when none exists.

#### 15.5.4 Build, installation, and reproduction

- Commands **MUST reflect current** `meson.build`, `meson.options`, Debian
  metadata, and actual executable/target names. Do not paste commands from
  another repository or include nonexistent options.
- Show a basic local build and installation workflow, plus headless, optional
  feature, development and packaging variants where they exist.
- Mark the actual minimum and preferred dependency versions, including where
  optional components can be absent, and link to the authoritative dependency
  manifest rather than duplicating a long list liable to drift.
- State if an in-tree executable requires a special worker/service path or
  environment variable. Do not require an undocumented internet download,
  privileged command or developer-specific absolute path to perform a build.
- Distinguish source builds from published binary installations, packaging
  qualification and project-specific prerequisites. Avoid presenting a
  release publication command as a successful verification of that release.

#### 15.5.5 Links, maintenance, and source of truth

- `README.md` MUST use working, repository-relative Markdown links for local
  files. Do not depend on one developer's Downloads directory or a temporary
  workstation path. External links SHOULD be stable and relevant.
- Link to **one current architecture document**, **one current API contract**
  per version where applicable, and the current standards. Store historical
  verification and milestone records separately from current documentation.
- Before release, cross-check README version, package names, feature switches,
  documented public calls and support tables against the source/build tree.
- When a change modifies a public method, supported format, runtime
  requirement, build option, CLI, settings contract, or installation path,
  update the README or its linked authoritative guide **in the same change**.
- Avoid duplicating exhaustive API specifications in multiple places; the
  README provides a navigable, accurate public index and links to the detailed
  reference. Do not invent benchmark values, CI outcomes or compatibility
  claims without recorded evidence.
- Markdown headings should be stable, descriptive and linkable; use fenced
  blocks with correct language tags, copyable commands, and readable tables.
  Images and badges are optional, never substitutes for factual text.

#### 15.5.6 README review checklist

A release or large structural change **MUST** review the README against:

- [ ] Project metadata is current and distinguishes product/API/ABI versions.
- [ ] Features and supported integrations are actually implemented.
- [ ] Optional support is clearly labeled and discoverable at runtime.
- [ ] Toolchain, dependencies, build options and packaging commands exist.
- [ ] Public interfaces, signatures, examples and links match installed APIs.
- [ ] Resource, ownership, cancellation and security constraints are stated.
- [ ] Local Markdown links resolve after file moves.
- [ ] Tests and qualification are described without claiming unrun checks.
- [ ] Architecture/contribution/standards references are current.
- [ ] License and material third-party provenance are accurately identified.

These checks apply across all Majoris projects; format- and codec-specific
facts belong in each owning repository, **not** in this cross-project policy.

---

## 16. Behavior-preserving refactoring and optimization

### 16.1 Before changing code

Capture a baseline:

- Git revision and current build profile.
- Public API/ABI exports and generated bindings.
- Unit/integration results and known expected failures.
- Numerical results, data formats, metadata, ordering, and timing behavior for representative fixtures.
- Memory, CPU, latency, allocation counts, cache hit rate, and worker cleanup for relevant workloads.

### 16.2 Safe refactoring sequence

1. Identify one focused change and its invariants.
2. Add a regression test if the behavior is not already protected.
3. Make one internal structural change.
4. Rebuild and run focused tests.
5. Run full and installed-consumer tests.
6. Compare API/ABI and numerical outputs.
7. Benchmark if performance is a motivation.
8. Document results and revert/regroup if correctness or speed regresses.

Do not combine unrelated renames, file movement, memory-management changes, and algorithm changes into a single unreviewable patch.

### 16.3 Optimization standards

- **Measure first.** Prefer profiling data over intuition about slow loops.
- Favor algorithmic improvements (region processing, bounded queues, caching, avoiding duplicate work) over premature micro-optimizations.
- Be cautious changing floating-point operations: reassociation, SIMD, precision conversion, rounding, and locale-sensitive transformations can change output.
- For exact-output paths, compare bytes/hashes; for numerical paths, define tolerances in advance and test edge values.
- Check memory peaks, not only steady-state size. Avoid materializing full datasets when bounded streaming or incremental processing is feasible and verified.
- Preserve a fast path and a correctness path when hardware or dependency capabilities differ; do not silently downgrade strict requirements.
- Remove redundant work only after confirming it is not required for security, ownership, metadata, or cache invariants.

### 16.4 Red flags

Stop and investigate when a refactor changes: exported symbols, IPC protocol shapes, data representation, numerical results, record ordering, timestamps, persistent data, cancellation semantics, default UI controls, cache keys, or package dependencies.

### 16.5 Design-pattern and declaration-style migration without functional or performance change

For pattern/structure/naming/`var` work that claims to be behavior-neutral, apply **all** of the following:

1. Before editing, inventory actual call graphs, extensibility forces, pattern participants, source dependencies, ownership edges, serializers, exported names, runtime hot paths and test seams. Classify each proposed change as *mandatory structural correction*, *verified naming/style correction*, *approved exception*, or *not needed*. Do not automatically migrate every class.
2. Baseline supported build profiles and installed consumers; record ABI, GIR/VAPI, GObject names, protocol bytes, decoded/numerical output, errors, cancellation ordering, and representative latency/RSS/allocation results.
3. First make mechanically equivalent **private** changes: move a responsibility or replace a local declaration only after proving exact type/ownership/behavior equivalence. Treat renames, pattern extraction, and `var` style as reviewable separate commits.
4. If introducing a Strategy/Adapter/Bridge/State/Proxy, verify interface contracts and independent selection; avoid adding virtual calls, object allocation, signal traffic, threads, or conversions to performance-critical loops. Preserve existing scheduling, backpressure, resource limits, and fallbacks.
5. Preserve externally visible identifiers and serialized values even if new private roles use different names. Provide a mapping at the boundary where needed.
6. Compare outputs and side effects, verify determinism and run security, cancellation, lifecycle, package, ABI and installed-consumer checks. Run matched performance measurements; do not dismiss a reproducible regression as "mere abstraction overhead".
7. If equivalence or performance cannot be established, **revert/defer** the structural rewrite and document a bounded exception (§20). A compelling class diagram alone is insufficient justification.
8. Finish with a finite compliance report: **compliant**, **corrected with evidence**, **documented exception**, or **non-applicable** per inspected pattern candidate. Do not create an indefinite refactoring backlog.

**Acceptance principle:** Design-pattern adoption MUST NOT silently change externally observable functionality, numerical behavior, security, ordering, cancellation, ownership, resource limits, ABI or supported platform performance. This does not mean that raw benchmark time can be mathematically identical on all systems; use repeated same-environment comparisons, measurement variance and an agreed regression policy to determine whether a change has harmed performance.


---

## 17. Testing strategy and CI

### 17.1 Test layers

| Layer | Examples | Expected cadence |
|---|---|---|
| Static checks | Formatting, import order, shell syntax, XML parsing, Meson lint where supported | Every change |
| Unit tests | Configuration parsing, flags, parser bounds, arithmetic, ownership helpers | Every change |
| Integration | GTK lifecycle, service protocols, storage, async callbacks | Every change where relevant |
| Installed consumers | Public C/Vala APIs, GtkBuilder, pkg-config, GIR | Every release/CI profile |
| Extended | Large datasets, repeated operations, long-running services, multiprocess contention | Nightly/pre-release |
| Security | Fuzzers, ASan/UBSan, malformed inputs, worker timeout/crash | CI/pre-release |
| Hardware | Input devices, display behavior, removable devices or accelerators, as relevant | Supported-hardware validation |

### 17.2 Determinism and isolation

- Use generated, deterministic, appropriately licensed fixtures.
- Give each test an isolated temp/cache/home location; avoid modifying real user settings.
- No network dependency for default tests.
- Skip optional-dependency/hardware tests with a clear, machine-readable reason, not a silent pass.
- Do not conflate mocked integrations or simulated hardware states with verified behavior on actual devices.
- Keep test commands repeatable; preserve artifacts/logs for failures.
- Register slow tests in Meson test suites rather than leaving them as undocumented manual commands.

### 17.3 Recommended CI matrix

- Debian 13 default debug build.
- Debian 13 optimized/release build.
- Headless build if supported.
- Optional backends explicitly on/off.
- Strict-warning diagnostic build.
- C/C++ sanitizer build (where the runtime permits).
- Installed public API consumers.
- Debian package build and clean install/upgrade checks.
- Extended integration/performance suite on an appropriate runner.

### 17.4 Review and evidence

Every final implementation report SHOULD state: what changed, why, tests actually run, exact results, optional tests skipped, limitations, ABI effects, packaging effects, and any measured performance difference. Never claim test success from source inspection alone.

### 17.5 Test tree organization and when to split directories

**Principle:** organize tests by **responsibility and execution contract**, not merely by source language. A test's location SHOULD tell maintainers what is being verified; its Meson suite SHOULD tell automation how/when it runs. These are different concerns.

A small project MAY keep a flat `tests/` directory if it remains easy to navigate. A project SHOULD introduce subdirectories when it has several distinct test responsibilities, a substantial number of test source files (roughly ten or more is a useful review trigger, not a limit), several independent fixture generators/runners, or a central Meson test file that has become difficult to review. Review complexity, ownership, and dependencies before splitting; avoid a directory for every individual test.

A typical **optional** layout for a larger repository is:

```text
tests/
├── meson.build              # shared setup and ordered subdir() calls
├── fixtures/                # immutable input files and manifests
├── support/                 # deterministic generators, isolation, shared helpers
├── unit/                    # focused API/algorithm tests
├── integration/             # end-to-end component interactions
├── security/                # untrusted input, isolation, fuzz harnesses
├── extended/                # long-running/stress/lifecycle cases
├── benchmarks/              # performance programs and measurement runners
└── release/                 # installed consumers, packaging and qualification
```

These names are examples, **not compulsory directories**. An application whose primary testing divisions are `storage/`, `services/`, and `ui/` MAY use those domain-oriented directories instead, with suites controlling cadence. Do not require both a `unit/` and a parallel technology-specific hierarchy when they would duplicate responsibilities.

For larger directories, further subdirectories MAY be added when they create a clear component boundary. A few focused test files in one directory are preferable to nested folders with a single trivial file each.

#### Placement rules

- `fixtures/` contains version-controlled, deterministic inputs, manifests, licenses, provenance, expected outputs, and optionally small golden files. **Generated** fixtures belong in the build tree or private test temporary directories, not the source tree.
- `support/` holds deterministic fixture generators, reusable subprocess/environment helpers, data builders, and test-only support libraries. Do not mix shared utilities with assertions that verify a specific subsystem.
- `unit/` contains focused, inexpensive tests of functions, public contracts, or narrow internal seams. Do not use implementation-language subdirectories as the only means of classification.
- `integration/` contains tests that combine components, services, GUI layers, public APIs, or subprocesses.
- `security/` contains trust-boundary checks, malformed input, worker isolation, parsers, and fuzz harnesses; it does **not** mean other test groups may ignore security behavior.
- `extended/` contains intentionally expensive stress/lifecycle/scale testing. A fast check of the same behavior may remain in `unit/` or `integration/`.
- `benchmarks/` contains measurement workloads and reproducible result runners, not nondeterministic pass/fail performance assertions in ordinary unit tests.
- `release/` contains installed-consumer checks, ABI/package qualification, and required release gates. Operating-system package setup MAY remain in a small shell helper.

Each test source SHOULD have one clear owner and purpose. Avoid duplicating the same test under multiple directories to include it in different suites: register it appropriately in Meson instead.

### 17.6 Choosing C, C++, Vala, Python, and shell for tests

The test language MUST be chosen for the **boundary under test**, not for cosmetic repository uniformity.

| Language | Preferred responsibilities | Avoid |
|---|---|---|
| C | C public/private APIs, GLib/GObject test harnesses, memory/bounds, ABI adapters | Reimplementing production behavior in a separate test algorithm |
| C++ | Native C++ behavior, exception safety, RAII/ownership, C ABI boundaries | Wrapping a simple language-native assertion in a custom cross-language runner |
| Vala | Vala APIs, GLib async, GObject, GTK widgets, signals and lifecycle | Moving direct Vala assertions to fragile subprocess-based text checks |
| Python | Multi-process orchestration, fixture generation, CLI tests, IPC checks, deterministic integration assertions, CI qualification, benchmarks | Reimplementing native code merely to make every test Python |
| Shell | Short package-manager commands, environment preparation, straightforward CI glue, portable single-purpose wrappers | Long test logic with nested pipelines, multiple background processes, embedded language snippets, and complex result parsing |

- Native tests SHOULD use established test frameworks where appropriate (`g_test_*`, C++ framework if present, Vala/GLib tests, Python `unittest` or pytest). Do not introduce heavyweight dependencies without a real need.
- A few lines of shell around Debian tooling are acceptable and often clearer than Python. A script's line count alone is **not** a failure: move orchestration when ownership, subprocess cleanup, assertions, quoting, or control flow become difficult to verify.
- Prefer Python when a shell script **compiles multiple consumers, manages concurrency/process groups, runs assertions on structured results, or contains embedded Python**. Keep short shell wrappers if they provide a clear platform/environment boundary.
- Test code should call real production APIs rather than duplicate protocol logic or decoder behavior. Assertions in a host-language runner MUST validate real observable results.
- Tests that exercise an application through its CLI or installed executable MAY use Python without being considered unit tests of Python.

### 17.7 Python orchestration and shell boundary

For nontrivial Python test runners:

1. Use import-safe modules with organized imports, a bounded `main()` entry point, argument validation, and explicit integer exit codes.
2. Group related operations into named, independently testable helpers (compile, execute, assert result, compare artifact, cleanup) without creating an `orchestrate_everything()` monolith.
3. Build subprocess commands as argument arrays, not interpolated shell strings. Set explicit timeouts. Capture/stream stdout and stderr usefully and retain command/return-code context on failure.
4. When running background processes, use a clear ownership model; terminate, wait for, and reap every owned child on success, assertion failure, signal, and timeout.
5. Isolate HOME, XDG directories, temporary files, and output paths; provide an explicit, test-local shared directory only for cases intentionally testing concurrency.
6. Avoid false passes: a missing required executable, fixture, or registered test must fail; an optional feature can skip only under the project's documented capability policy.
7. Keep actual test assertions in normal functions/modules rather than inline `python -c` or heredocs within long shell scripts. Shell snippets remain acceptable for genuinely trivial environment checks.
8. Protect CI/release automation against missed tests: check registration **and** recorded results where qualification requires both.

Shell helpers that remain SHOULD use a clear interpreter line, `set -eu` where compatible, correct quoting, explicit working-directory assumptions, and uncomplicated cleanup. POSIX shell scripts MUST be validated with `sh -n`; Bash-only features require an explicit Bash interpreter and declared dependency. Do not blindly replace platform-provided shell commands with fragile custom Python equivalents.

### 17.8 Test filenames, ordering, imports, and comments

- Use descriptive filenames consistent with each language: `test-request-store.c`, `test_request_store.py`, `request-store.vala`, etc. Preserve names that form an installed/public compatibility contract or would create unnecessary churn.
- Follow §4–§8 for includes, imports, constants, helper declarations, function order, ownership and American English. The code in tests is **production-quality engineering code**, not exempt from formatting or error handling.
- A unit test SHOULD read as **setup → action → assertion → cleanup**, using the host framework's fixtures where appropriate. Group tests by behavior. Do not force artificial abstraction for a short one-off fixture.
- Make assertions specific: include input, expected/actual values, relevant state and helpful failure context. Test failure paths and cleanup, not only successful execution.
- Comments SHOULD explain why a fixture, limit, tolerance, race window, or skip condition exists, not repeat the assertion. Include references to external regression cases or standards where useful.
- Arrange a test source logically: own imports/includes, constants, local fixture types/helpers, individual tests grouped by feature, registration, and a thin entry point when required.
- Deduplicate helpers only when the resulting shared abstraction reduces complexity. Avoid a giant `test_utils` module with unrelated responsibilities.

### 17.9 Meson suite membership, fixtures, and path stability

- Keep Meson test names **stable** through source moves unless renaming is intentional, reviewed, and all CI/release consumers are updated. Qualification scripts may depend on exact names; compare the pre-/post-change `intro-tests.json` inventory.
- Preserve suite membership, options, timeout values, env variables, dependency/feature guards, skip behavior, working-directory assumptions, and `depends` relationships. Merely relocating `meson.build` can change output paths and target references.
- Declare generated fixtures with Meson targets and dependencies. Prefer stable paths or pass generated targets to downstream tests. If a well-known `build/tests/...` path is used by packaging/release jobs, **preserve it initially** or update every referenced workflow and verify the installed test in the same change.
- Keep fixture generators in shared setup when multiple suites depend on them. Do not duplicate generation or generate fixtures implicitly as a side effect of a test running first.
- Test-directory Meson files SHOULD have this order when relevant: feature conditions/dependencies; source/fixture references; executables; `test()` and `benchmark()` registration; documented exceptions.
- A small coordinator `tests/meson.build` SHOULD declare shared resources and invoke test-specific `subdir()` files in dependency order. Use Meson source objects, absolute paths, or declared build targets rather than fragile relative paths.
- Do not silently exclude test suites from `meson test` through build-option changes. Expensive tests MAY be registered conditionally when required dependencies/flags exist, but their release qualification contract must be explicit.
- Inspect source archives, packaging lists, permissions, and CI path filters after moving test scripts. A source move must not drop fixtures or install-time test consumers.

### 17.10 Behavior-preserving test-suite migration

Reorganizing tests is a **nonfunctional refactor** and MUST be reviewed separately from new test coverage or production fixes where practical.

Before moving files, record the existing Meson test inventory, suites, options, registrations, timeouts, fixture paths, artifact locations, build variants, installed checks, and CI entry points. Then:

1. Move one cohesive group at a time, preferably with Git-aware renames so history remains reviewable.
2. Update its Meson target, input references, helper imports, generated fixture paths, docs, and CI commands in the same focused step.
3. Run the affected test or validate its registration immediately; compare suites and skip behavior against the baseline.
4. Refactor a large shell runner to Python as a **separate step** after relocation; verify the same commands, outputs, exit codes, environment, installed-versus-build-tree selection, and cleanup semantics.
5. Apply formatting and code-organization changes in reviewable commits, isolated from behavioral fixes. Confirm generated/vendor files are not reformatted.
6. Run all applicable build profiles, native tests, GTK tests, security/extended checks, release qualification, and installed-consumer checks.
7. Produce a pre/post inventory and explain every intentional test addition, removal, skip, or change of registration. An unexplained reduction in required tests is a regression.

Avoid assuming that a source move is safe because it compiles: installed tests, generated fixture paths, CI, and packaging scripts are part of the test system.

### 17.11 Test organization review checklist

- [ ] Test layout reflects responsibilities and remains proportional to repository size.
- [ ] Each test implementation uses a language appropriate to the API or behavior being tested.
- [ ] Substantial orchestration is in maintainable Python or an established test runner; short shell helpers remain when they are the clearest choice.
- [ ] No complex assertions or multi-process ownership are hidden inside shell heredocs/background loops without adequate structure.
- [ ] Entry points are thin; helpers have clear names, error contracts, and cleanup ownership.
- [ ] Test sources follow project naming, include/import order, function/constant order, comments, and American English conventions.
- [ ] Shared test helpers are cohesive and do not duplicate application logic.
- [ ] Meson test names, suites, timeouts, feature gates, and required registrations are unchanged unless intentionally revised.
- [ ] Generated fixtures remain in declared build locations; required release fixture paths are preserved or fully migrated.
- [ ] Each test owns its temporary state; deliberate cross-process sharing is limited to its own scope.
- [ ] Source paths in CI, source-release checks, documentation, and installed-consumer tests remain valid.
- [ ] Pre/post inventories and actual results are documented; unavailable checks are reported as not run.
- [ ] Test filenames distinguish executable tests from runners, generators, and fixtures; functions and case paths describe verified behavior.
- [ ] Meson test names are consistently human-readable; intentional renames update exact-name release and CI consumers.
- [ ] GTK test-window defaults are explicit where applicable, with documented exceptions for geometry-dependent cases.
- [ ] Coordinate-dependent tests validate mapped/allocated widgets and scale assumptions before synthetic interaction.

### 17.12 Test identifiers, names, and result diagnostics

**Principle:** names should identify the behavior under verification and remain discoverable, readable, and stable for automation. Distinguish the **source filename**, **compiled target**, **Meson test name**, **individual test case/path**, and **test fixture/helper**; they serve different audiences and need not be identical. Naming conventions apply to project-owned test code and must not override upstream test-framework or public compatibility identifiers.

#### 17.12.1 Test-source and helper filenames

- Executable **C, C++, and Vala test source files** SHOULD use `test-<feature-or-behavior>.c`, `.cpp`, or `.vala` (for example, `test-record-store.c`, `test-service-lifecycle.vala`). Include a specific behavior when a generic component name would be ambiguous; avoid misleading specificity.
- Python files discovered by `pytest` or `unittest` SHOULD use `test_<feature_or_behavior>.py` or the framework's documented discovery convention.
- Executable Python orchestration, benchmark, verification, and generator scripts SHOULD use action-oriented `snake_case.py`, such as `run_integration.py`, `check_package.py`, or `make_fixtures.py`. These are **runners/helpers**, not necessarily test cases and should not be renamed to `test_*.py` for cosmetic uniformity.
- Native fixture generators, stubs, injection modules, and test-support executables SHOULD use responsibility-based names such as `make-fixtures.c`, `fault-worker.c`, or `mock-provider.vala`, not `test-` unless they independently perform assertions as test programs.
- Avoid bare names such as `test.c`, `exercise.vala`, `checks.py`, `helpers.c`, or names whose declared scope is broader/narrower than their actual assertions. Preserve existing public filenames and versioned artifact references where renaming would create avoidable compatibility disruption.
- Use one separator convention per file category: **kebab-case** for C/C++/Vala sources; **snake_case** for Python modules. Do not blindly rename generated, vendored, or external files.

#### 17.12.2 Test functions, case paths, and granularity

- Standalone assertion functions SHOULD have descriptive names with a consistent pattern, such as `test_<behavior>()`, `verify_<contract>()`, or an established framework equivalent. `verify_` is appropriate for a reusable integration assertion helper; `test_` identifies a discoverable or registered test case.
- Setup and support helpers SHOULD use verbs reflecting their action: `create_fixture()`, `load_reference_data()`, `assert_state()`, `wait_for_ready()`, `dispose_fixture()`. Avoid uninformative `exercise()`, `fixture()`, `verify()`, `run_test()` when the name alone does not communicate the responsibility.
- For GLib `g_test_*`, register hierarchical paths that describe a **component and a specific behavior**, for example `/storage/records/invalid-key` or `/ui/window/activation`. Paths SHOULD be lowercase, stable, and consistently delimited. Use existing framework-discovery identifiers when a language requires them.
- Divide unrelated assertions into focused cases so failures identify the broken contract. A single integration scenario MAY contain several dependent stages when their **sequence is what the test verifies**; do not split it merely to maximize the test count or force duplicated expensive setup.
- Parameterize equivalent variations (for example, supported input variants or scaling factors) where the framework supports clear per-case reporting. Each case needs a meaningful failing input/variant identifier.
- Include expected and actual values or the relevant operation in assertion diagnostics. Avoid positive-looking output after a failed intermediate stage. Timeouts, skips, and asynchronous failures MUST identify the stage that failed.
- Test-window titles, temporary file names, and log labels SHOULD identify the running test when doing so improves diagnosis; they MUST NOT become hidden correctness dependencies.

#### 17.12.3 Meson names and automated qualification

- Use concise, descriptive, **sentence-case** human-readable Meson `test()` names, beginning with an uppercase word where practical, while preserving official acronyms and upstream spellings (for example, `API`, `CLI`, `GTK`, `SQL`, `D-Bus`). Avoid an arbitrary mixture of sentence case, lowercase descriptions, opaque filenames, and machine-style hyphenated identifiers.
- Name tests after the verified **observable behavior**, not the language, helper program, framework boilerplate, or internal implementation detail. Do not prepend the suite name merely because it belongs to `unit` or `integration`; Meson already records the suite.
- Keep a stable Meson name for each registered test through ordinary refactoring and source moves. **Renaming a Meson test is a deliberate migration**, not a formatter side effect. If a test name changes, update all exact-name consumers in qualification scripts, CI filters, docs, baseline inventories, and dashboards in the same patch.
- A release-qualification runner MUST verify **both** registration and the actual passing result of every mandatory test. Name changes MUST NOT weaken required-test sets, convert required failures into skips, or introduce substring/wildcard matching that accidentally accepts the wrong test.
- For long-lived machine consumers, a stable machine-readable **test ID or manifest** MAY be maintained separately from display names, but only if introduced deliberately and checked consistently. Do not invent a new ID registry merely to avoid updating a small number of exact-name references.
- Report a pre/post inventory of names, suites, conditions, timeouts, and test results. A name-only cleanup should have a one-to-one mapping of required cases and unchanged effective coverage.

### 17.13 GUI test windows, sizing, and mapped geometry

**Principle:** GUI test geometry must be intentional, reproducible, and validated at the layer actually used by assertions. An explicit default size is a **request**, not proof that the window manager or compositor allocated that exact size. Use **logical pixels** for GTK4 window-size policy and do not confuse them with physical screen pixels, device scale, widget allocations, or offscreen render targets.

#### 17.13.1 Size categories and exceptions

For standard interactive GTK test surfaces, use a small number of **suggested defaults**, overridable according to the behavior under test:

| Category | Suggested logical size | Typical purpose |
|---|---:|---|
| Compact | 640 × 480 | Single-widget lifecycle, installed API, or accessibility test |
| Standard | 800 × 600 | Multi-widget integration, navigation, or general UI behavior |
| Large | 960 × 720 | Full-layout demos, visual inspection, or more complex arrangements |

These values are **guidance**, not mandatory universal dimensions. A test that verifies narrow/ultrawide layouts, scrolling, minimum sizes, resize handling, scale factors, or precise input coordinates MAY and SHOULD use the specific dimensions needed for that behavior; record a short rationale near the fixture or test setup. Do not change a geometry-sensitive existing test merely to fit a category.

- GTK window-creating tests SHOULD set an explicit default size (`gtk_window_set_default_size()` in C or the Vala equivalent), unless the actual purpose is to test toolkit-natural/default sizing.
- Reusable helper functions MAY centralize default dimensions, titles, and window construction, provided tests can override them and those helpers do not create extra visual UI or style classes.
- Example/demo applications SHOULD choose sensible explicit default sizes where they present a window, but their sizes MAY differ from automated test sizes. Preserve intentional product-design and demonstration layouts.
- Do not force a particular screen resolution, decoration size, or global theme on every test; provide test-specific display fixtures and document any required backend or scaling conditions. Never insert application CSS solely to normalize test geometry.
- Set a useful window title for manually inspected/debuggable test windows, unless title or window decoration behavior itself is being tested. Titles must not be used as a fragile readiness signal.

**Illustrative Vala GTK4 test setup:**

```vala
var window = new Gtk.Window ();
window.title = "Component lifecycle test";
window.set_default_size (640, 480);
window.child = view;
window.present ();
```

**Illustrative C GTK4 test setup:**

```c
GtkWindow *window = GTK_WINDOW (gtk_window_new ());
gtk_window_set_title (window, "Component integration test");
gtk_window_set_default_size (window, 800, 600);
gtk_window_set_child (window, content);
gtk_window_present (window);
```

Apply the repository's documented spacing/brace style rather than treating these examples as literal formatter output.

#### 17.13.2 Geometry-sensitive assertions

- If a test synthesizes pointer, touch, keyboard, scrolling, drag, or coordinate-dependent input, first wait for the intended window and widgets to be **realized/mapped and allocated**. Use a bounded, event-driven wait when possible; do not rely on `present()` followed by an unexplained fixed sleep.
- Assert the **actual allocated widget or content-area geometry** that the subsequent action requires, including hit targets and visible viewport bounds. An exact window allocation SHOULD be required only when the environment guarantees it and that exact dimension is the contract being tested.
- For coordinate-sensitive input, derive test coordinates from actual widget allocations/transforms where practical instead of hardcoding values tied to a window-manager border or titlebar. If fixed coordinates are part of a deliberate regression case, document and assert their prerequisites before interacting.
- Distinguish GTK logical coordinates from physical device pixels. Test applicable scale factors (for example, `GDK_SCALE=1` and `2`) and supported backends where practical; success under X11 does **not** prove Wayland or real touchscreen behavior.
- Do not use `gtk_widget_set_size_request()` as a substitute for a window's default size. A child minimum size larger than the window can be intentional for scroll testing; explain that relationship rather than increasing every window to fit it.
- Verify relevant geometry again after resize, remap, or scale changes when those transitions affect the test contract. Do not add arbitrary size assertions to headless, offscreen, or pure API tests that have no window geometry requirement.
- Use bounded timeouts and report expected vs. allocated dimensions on failure. Skip only under the approved capability policy; missing mandatory display/backend dependencies must fail release qualification where required.

#### 17.13.3 GUI test stability and cleanup

- Create each test window with clear ownership; destroy it and disconnect temporary handlers on every completion path. Ensure asynchronous work cannot update a disposed widget.
- Tests MUST NOT depend on the host user's actual desktop, saved window geometry, theme preferences, monitor arrangement, or other mutable settings unless those properties are the explicit subject of a platform test.
- Visual screenshot/golden-image tests must declare the rendering environment (GTK version, theme, fonts, scaling, backend) and maintain appropriately versioned references. Default-size uniformity alone cannot establish screenshot comparability.
- Keep GTK XML layout ownership and Majoris Theme responsibilities intact; test standardization does not authorize hardcoded colors, padding, or styling.

### 17.14 Test naming and geometry standardization procedure

For existing projects, treat test renames and GUI-size cleanup as a **focused, nonfunctional migration**:

1. Inventory source files, individual test functions/paths, Meson target and test names, suite memberships, run conditions, exact-name qualification dependencies, and existing GUI-window defaults.
2. Identify whether each name accurately describes behavior and whether each GUI size is intentionally geometry-sensitive. Document exceptions before modifying them.
3. Rename files and helpers in small, Git-aware steps; update Meson paths, imports, source references, CI, qualification, docs, and any fixture lookup rules together. Preserve registered test coverage.
4. Apply consistent Meson display names using an explicit old-to-new mapping. Verify fail-closed release qualification after every mapping change; do not relax exact required-test assertions.
5. Give unspecified GUI windows appropriate defaults; preserve documented special sizes. Add allocation/readiness assertions to coordinate-sensitive tests, not meaningless exact-size checks everywhere.
6. Run formatting, build, fast, extended, security, backend/scale, installed-consumer, and release checks that apply. Compare pre/post test inventories, effective assertions, target paths, skips, failure behavior, and API/ABI effects.
7. Record any unavailable environment or hardware verification as **not run**. Do not claim platform-specific visual consistency from source inspection alone.

### 17.15 GoF and Vala-declaration conformance tests

- Pattern compliance reviews SHOULD include static dependency direction checks, a documented participant/intent map, and targeted behavioral tests for at least two implementations where a genuinely interchangeable contract exists.
- For Adapter/Proxy/Decorator/Strategy substitutions, verify equivalent outputs, errors, cancellation, ownership and source freshness. For Observer and State-related changes, verify subscriptions/disconnects, ordering, stale callback suppression and disposal. For Singleton, verify controlled initialization and test isolation.
- Where proposed refactoring removes backend-name comparisons or changes internal dispatch, assert that all historical protocol strings, serialized data, names, and public signals/properties retain their values and behavior.
- Vala `var` migration MUST be assessed via the Vala compiler and type/ownership review, not a regex-only formatter. New local declarations should follow §7.5; existing explicit declarations intentionally expressing numeric width, nullability, interface type or ownership remain compliant.
- A project MAY use a source-aware lint rule to report obviously redundant local explicit declarations, but MUST NOT rewrite types automatically, impose a `var` percentage, or flag required explicit types as violations.
- Acceptance evidence includes the public API/ABI inventory, generated C comparisons where relevant, complete existing regression checks, and matched memory/latency benchmarks for touched hot paths. **Not run** is not **passed**.


---

## 18. Repository automation templates

These templates are **starting points**. Each repository MUST confirm compatibility with its minimum installed tool versions and existing conventions before adopting them.

### 18.1 `.editorconfig`

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space

[*.{c,h,cpp,hpp,cc,hh,vala,vapi}]
indent_size = 4
max_line_length = 100

[*.py]
indent_size = 4
max_line_length = 88

[meson.build]
indent_size = 2

[meson.options]
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

### 18.2 `.clang-format` (proposed C/C++ baseline)

```yaml
BasedOnStyle: GNU
IndentWidth: 4
ContinuationIndentWidth: 4
ColumnLimit: 100
UseTab: Never
SortIncludes: true
IncludeBlocks: Preserve
PointerAlignment: Right
BreakBeforeBraces: Linux
AllowShortBlocksOnASingleLine: Never
AllowShortFunctionsOnASingleLine: None
AllowShortIfStatementsOnASingleLine: Never
AllowShortLoopsOnASingleLine: false
AllowShortCaseLabelsOnASingleLine: false
MaxEmptyLinesToKeep: 1
KeepEmptyLinesAtTheStartOfBlocks: false
```

Adjust the template for a repository that already follows the upstream GNOME two-space C style. The short-block settings deliberately prevent collapsed function and control bodies. Formatter option availability depends on the supported `clang-format` version; validate the configuration against the installed version before enforcing it in CI. Format-only changes MUST be isolated from functional changes, and include-group boundaries should be reviewed after formatting. The configuration does **not** apply to Vala, Meson, Python, or shell.

### 18.3 `pyproject.toml` Ruff example

```toml
[tool.ruff]
line-length = 88
indent-width = 4
# Set target-version to the actual minimum supported Python version.

[tool.ruff.lint]
select = ["E4", "E7", "E9", "F", "I", "B", "UP"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

Use `ruff check .` and `ruff format --check .` in CI. Do not auto-fix generated or vendored sources. If tool versions differ across repositories, pin a supported minimum or a CI version.

### 18.4 Suggested verification commands

```bash
# C/C++ formatting (only when clang-format is installed)
clang-format --dry-run --Werror native/*.c native/*.cpp

# Python lint and formatting
ruff check .
ruff format --check .

# Meson build and test
meson setup build -Dbuildtype=debug
meson compile -C build
meson test -C build --print-errorlogs

# Independent diagnostic build (use separate build directory)
meson setup build-check -Dwarning_level=3 -Dwerror=true
meson compile -C build-check
meson test -C build-check --print-errorlogs

# Debian binary packages, for repositories providing debian/
dpkg-buildpackage -us -uc -b
```

These are examples: source globs may omit nested files, warning policy may require staged adoption, and optional features must use the repository's actual Meson option names. Add appropriate build/test/packaging commands to each project's `CONTRIBUTING.md`.

---

## 19. Pull-request and Codex acceptance checklist

### 19.1 Source organization and naming

- [ ] This standard is applied without inserting examples, assumptions, or dependencies from an unrelated application domain.
- [ ] Code uses American English where project-owned and externally safe.
- [ ] C/C++/Vala control structures and function bodies are multiline even when they contain one statement; there are no compressed inline `if`, `else`, loops, or catches.
- [ ] Blank lines mark actual logical groups: no repeated empty lines inside C/C++/Vala/Meson functions; Python follows PEP 8 top-level and method separation.
- [ ] Wrapping and continuation indentation are readable, and unrelated statements are not combined onto one line.
- [ ] Names describe behavior and use the correct language conventions.
- [ ] C/C++ includes, Vala `using` directives, and Python imports are ordered and deduplicated.
- [ ] Constants, types, fields, constructors, functions, and methods follow a predictable order.
- [ ] File/module responsibilities remain cohesive; no unnecessary layers were created.
- [ ] `main()` and other process entry points remain thin bootstrap/dispatch boundaries; substantive work is in cohesive, testable components.
- [ ] Startup/shutdown order, error exits, and ownership are explicit; no hidden side effects occur on import or initialization.
- [ ] Comments document intent, safety, invariants, and public contracts rather than obvious statements.
- [ ] No redundant product prefix appears in private implementation identifiers.
- [ ] Tests are placed by responsibility, with subdirectories only where their size and complexity warrant them.
- [ ] Test implementation languages match their target APIs; complex orchestration is not buried in shell scripts.
- [ ] Test `main()` functions, assertions, imports/includes, and test-only helpers follow the same engineering standards as production code.
- [ ] Test source files obey the same multiline control-flow and vertical-spacing rules; tests do not use inline assertions or empty catches to obscure failure paths.
- [ ] Test filenames, registered test names, case paths, and helper functions describe actual behavior consistently.
- [ ] GUI tests set intentional logical-pixel defaults (unless testing natural sizing) and preserve purpose-specific geometry.
- [ ] Input tests verify relevant mapped widget allocations and scale assumptions before synthetic events.

### 19.2 Correctness, ownership, and security

- [ ] All behavior and defaults remain compatible unless explicitly requested otherwise.
- [ ] Source and generated API/ABI identities remain correct.
- [ ] C/C++ ownership and cleanup cover every error path.
- [ ] Vala async cancellation and stale-callback protection remain correct.
- [ ] Caches and worker queues remain bounded.
- [ ] Input sizes, offsets, and resource limits are validated safely.
- [ ] Sandbox boundaries remain intact.
- [ ] Data transformation, persistence, UI state, timing, and protocol behavior retain documented correctness.

### 19.3 Build and release

- [ ] Meson files are grouped and ordered by responsibility and dependency.
- [ ] Entry-point sources appear only in intended executable targets; no reusable library accidentally includes `main()`.
- [ ] Optional dependencies can be disabled without unresolved references.
- [ ] Headers, pkg-config, VAPI, GIR, XML, and installed paths are correct.
- [ ] Debian binary package names and dependencies match their SONAME/ABI contracts.
- [ ] Git/source archives preserve required executable permissions.
- [ ] Static checks, build, unit tests, integration tests, and installed-consumer tests were run where possible.
- [ ] Test source moves preserved Meson names, suites, timeouts, dependencies, fixtures, and qualification requirements.
- [ ] CI, release scripts, generated fixture paths, and documentation reference the updated test locations.
- [ ] Required test inventory and actual results were compared before and after reorganization.
- [ ] Meson test-name migrations preserve mandatory qualification checks and do not introduce silent passes or skips.
- [ ] Relevant GTK tests were verified at supported scale/backend configurations; untested platform conditions are reported.
- [ ] Extended and hardware-only checks are explicitly recorded as run, skipped, or unavailable.
- [ ] The change report lists functional changes separately from formatting-only changes.

### 19.4 GoF architecture and Vala type-inference acceptance

- [ ] Applicable GoF patterns have an identifiable problem, correct participant roles, dependency direction, ownership contract and meaningful names (§2.5, §3.5).
- [ ] Inapplicable GoF patterns were **not** introduced merely to satisfy a catalog; false pattern labels were corrected or documented as pattern-like idioms.
- [ ] Public API and serialized identifiers remain stable; implementation names do not leak across unrelated modules.
- [ ] Backend-specific behavior is encapsulated behind an appropriate private capability/strategy/adapter boundary where extensibility genuinely requires it; a simpler fixed selection is permitted when justified.
- [ ] Composition, interface substitution, lifecycle and signal disconnection rules are followed; no unnecessary class hierarchies, Manager classes, or global service locators appeared.
- [ ] Vala locals with clearly inferable intended types prefer `var`; intentional explicit declarations for interfaces, nullable state, numeric width, ownership and API signatures are preserved (§7.5).
- [ ] No regex-only `var` rewrite occurred; minimum supported `valac` and relevant generated C were checked when ownership or numeric semantics might change.
- [ ] The change is proved behavior/API/ABI/serialization/security/cancellation equivalent and does not introduce a demonstrated performance or memory regression (§16.5).
- [ ] Architecture evidence and exceptions are recorded; the change has a finite stopping point rather than generating speculative follow-up refactoring tasks.


### 19.5 Mandatory declaration documentation verification

- [ ] Every handwritten Vala/C/C++ class, interface, enum, constructor, method, function and property has a tool-recognized meaningful description (§15.2).
- [ ] Public Vala signals and important enum members, C/GObject pointer ownership, nullable results and asynchronous finish/cancel semantics are documented accurately.
- [ ] All handwritten Python modules/classes/functions have PEP 257 docstrings, including test tools and entry points.
- [ ] Documentation-coverage tooling identifies missing declarations and exemptions without mistaking filler comments for valid documentation.
- [ ] Changes to documentation have not altered executable behavior, ABI, GIR/VAPI, protocol fields, dependencies, concurrency, packaging or benchmark-sensitive operations.
- [ ] Compiler/documentation toolchain checks and existing tests are reported as **passed**, **failed** or **not run**, never inferred from source inspection.

---

## 20. Exception and migration procedure

When a rule would break compatibility or make the code less clear:

1. Identify the exact rule and conflicting requirement.
2. Describe the scope (specific file, API, platform, or dependency version).
3. Record the reason in project documentation or the code review.
4. Preserve existing behavior and supported platforms.
5. Add compatibility tests if a public interface or serialized format is involved.
6. Revisit the exception when its upstream constraint changes.

A project MAY maintain a short `docs/standards-exceptions.md` listing intentional differences. Do not let undocumented exceptions accumulate into contradictory styles.

### Staged adoption across established repositories

**Pass A — Audit:** catalog code boundaries, public APIs, naming exceptions, code style, build profiles, and known problems.  
**Pass B — Correctness and packaging:** fix confirmed defects, security problems, ABI/package inconsistencies and missing tests.  
**Pass C — Formatting and ordering:** expand compressed control flow and function bodies, remove unnecessary blank-line gaps, format C/C++, normalize Python, organize Vala and Meson files, standardize entry-point and declaration ordering, update comments and names without changing behavior. Organize larger test suites by responsibility and migrate complex shell orchestration to Python in a separate reviewable step, preserving all required test contracts.  
**Pass D — Refactor:** trim oversized entry points, extract internally cohesive helpers and eliminate duplication with tests at each step.  
**Pass E — Optimize:** profile, change only measured bottlenecks, compare numerical/behavioral outputs and resource use.  
**Pass F — Release:** verify ABI, installed consumers, clean packages, source archive permissions, docs, and CI results.

Codex tasks SHOULD target one pass or bounded subsystem at a time rather than asking for a single massive unreviewable rewrite.

### GoF/`var` adoption rule for mature repositories

A request for strict pattern adherence or preferred `var` style MUST start with an **inventory**, not a mass rewrite. Identify true pattern instances and missing variation boundaries; mark patterns without an applicable force as **non-applicable**. Refactor only a bounded, evidenced mismatch, preserving released APIs and hot-path behavior. Standardize inferred local declarations with a language-aware conversion review, leaving explicit types where required by §7.5. If equivalent behavior and resource use cannot be proved, retain the current design as a documented bounded exception and complete the release; do not reopen the same hypothetical issue in every audit.


---

## 21. External references and rationale

These standards are Majoris project policy informed by, but not identical to, upstream conventions. The upstream documents are authoritative for their own tools and APIs:

- **GNOME C style:** https://developer.gnome.org/documentation/guidelines/programming/coding-style.html
- **GTK coding style:** https://github.com/GNOME/gtk/blob/main/docs/CODING-STYLE.md
- **Vala reference manual:** https://gnome.pages.gitlab.gnome.org/vala/manual/index.html
- **Vala variable declarations and inferred local types:** https://gnome.pages.gitlab.gnome.org/vala/manual/statements.html
- **Vala compiler style guidance (`var` commonly used):** https://docs.vala.dev/guides/compiler-guide/02-00-environment-setup.html
- **Vala memory ownership (`owned`/`unowned`/`weak`):** https://docs.vala.dev/guides/memory-management.html
- **Gang of Four source:** Erich Gamma, Richard Helm, Ralph Johnson, and John Vlissides, *Design Patterns: Elements of Reusable Object-Oriented Software* (Addison-Wesley, 1994). The 23-pattern vocabulary is a reference catalog, not a list of mandatory implementations.
- **Python PEP 8:** https://peps.python.org/pep-0008/
- **Ruff configuration:** https://docs.astral.sh/ruff/configuration/
- **Clang-format options:** https://clang.llvm.org/docs/ClangFormatStyleOptions.html
- **Meson built-in options:** https://mesonbuild.com/Builtin-options.html
- **Meson feature options:** https://mesonbuild.com/Build-options.html
- **Debian Policy — shared libraries:** https://www.debian.org/doc/debian-policy/ch-sharedlibs.html

**Maintenance policy:** Review this standard when adopting a new toolchain, new GTK/GNOME generation, new Debian base, new public ABI, or another major repository architecture. Update the version and summarize policy changes; do not silently rewrite the standard while code tasks are in progress.
