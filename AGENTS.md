# AGENTS.md

Guidance for AI agents working in this repo. Every line is something an agent
would likely get wrong without it.

## Read this first

**`CLAUDE.md` is stale and actively misleading.** It describes a vcpkg +
`build.py` + SDL3 + `install/` workflow that no longer exists. Ignore its
Build/Run/Client sections. The current system is **Conan 2 + CMake presets +
GLFW/OpenGL3/ImGui/miniaudio**, output to `build/<build_type>/`. This file is
the source of truth; verify against `build.sh`, `build.bat`, `conanfile.txt`,
and the root `CMakeLists.txt` if anything conflicts.

## Build

Conan 2 manages deps (`conanfile.txt`); CMake 4.2.3+ builds. Use the wrappers,
which run `conan install` -> `cmake --preset` -> `cmake --build --preset`:

```sh
# Linux / macOS (run from repo root)
./build.sh [Debug|Release] [--target TARGET] [--mir2x-res PATH] [--proxy]
# Windows
build.bat [Debug|Release] [--target TARGET] [--mir2x-res PATH] [--proxy]
```

- Default build type is **Release**. Configure preset is `conan-default`; build
  presets are `conan-release` / `conan-debug`.
- **C++ standard is 26** (CMakeLists sets `CMAKE_CXX_STANDARD 26` on non-MSVC;
  MSVC uses `/std:c++latest`). `build.sh` passes `compiler.cppstd=26`. Requires
  a recent GCC on Linux; MSVC on Windows.
- Conan is invoked with `-c "tools.cmake:configure_args=['-DCMAKE_POLICY_VERSION_MINIMUM=3.5']"`
  so CMake 4 can build older upstream packages (e.g. g3log). This does **not**
  change mir2x's own policies.
- ccache is auto-detected if installed.
- Output binaries land in `build/Release/` (Debug gets a `d` postfix on libs).
  `run.sh`/`run.bat` launch straight from there — there is no separate
  `install/` step in the normal dev loop (an `install()` target + CPack ZIP
  exists but is not what the run scripts use).

## Resources (mir2x_res)

Client/server game assets are packed from a separate `mir2x_res` checkout by
`tools/installres/src/install_res.py`, driven by the CMake **`zsdbdeploy`**
target. Resource path is resolved in this order: `--mir2x-res` flag >
`MIR2X_RES_REPO_PATH` env > `../mir2x_res` sibling dir. Building the
`zsdbdeploy` target **requires** a resource dir to be present (the wrappers
error out otherwise). `zsdbdeploy` deploys to `build/<type>/res` (client) and
`build/<type>/` (server), and copies `server/script/` next to the server exe.

## Run

```sh
./run.sh [Debug|Release] [--auto]   # Linux: starts server, then client
run.bat [Debug|Release] [--auto]    # Windows
```

With `--auto`, client connects to localhost and auto-logs in as `test:123456`.
The server binary defaults to master/"monoserver" mode; `--slave
--master-ip=... --master-port=...` runs a headless distributed map peer;
`--actor-pool-thread=N` sizes the actor thread pool.

## Checks

There is **no unit-test suite and no test stage**. The only check is
`tools/pyluacheck/src/pyluacheck.py`, which runs `luac -p` on a Lua file and
recursively syntax-checks string literals that look like embedded Lua code.
Usage: `python pyluacheck.py [luac-path] <file-path>` (run over files in
`server/script/`).

## Architecture (verified)

C++26 reimplementation of Legend of Mir 2 v1.45. `client/` + `server/` share
`common/` (static lib); ~30 helper tools under `tools/`.

### Server — actor model on coroutines
- `common/src/corof.hpp`: `awaitable<T>` (symmetric transfer), `eval_poller<T>`
  for polled coroutines. Request/response is `co_await m_actorPod->send(...)`;
  `post()` is fire-and-forget.
- `server/src/actorpool.hpp` `ActorPool`: thread pool, CAS-locked mailboxes,
  work stealing, injects `AM_METRONOME` for time-based ticks.
- Actor hierarchy: `ServerObject` (owns `ActorPod`) -> `CharObject` (map/move
  protocol TRYLEAVE/ALLOWLEAVE/LEAVEOK/FINISHLEAVE) -> `BattleObject` ->
  `Player`/`Monster`; plus `NPChar`, `ServerMap`, `ServerGuard`, `Quest`.
- `ServiceCore` (`servicecore.hpp`, extends `PeerCore`) is the central
  coordinator (login, char creation, map loading, quests); receives
  `AM_RECVPACK` from `netdriver.hpp` / `actornetdriver.hpp`.
- Message types: `ActorMsgPackType` enum + packed structs in
  `server/src/actormsg.hpp`.
- The server monitor GUI is **ImGui** (server links `imgui::imgui`), **not
  FLTK** as CLAUDE.md claims. FLTK survives only in two tools
  (`herowil2png`, `weaponwil2png`).

### Client — GLFW + OpenGL 3.3 + ImGui + miniaudio (NOT SDL3)
- `client/src/gldevice.hpp` `GLDevice`: GLFW window + OpenGL 3.3 renderer. All
  drawing goes through `ImGui::GetBackgroundDrawList()`. ImGui is a **rendering
  backend only**, not the GUI framework.
- `client/src/audiodevice.hpp` `AudioDevice`: miniaudio engine (replaces
  SDL_mixer). BGM/SFX decode at play time from raw bytes.
- GUI is a custom **retained-mode** framework: `widget.hpp`
  (`Widget`/`WidgetTreeNode`, `std::variant`+lambda dynamic properties).
  Concrete panels are `*Board` classes aggregated by `GUIManager` (owned by
  `ProcessRun`). See `GUI.md` for a deep breakdown.
- Scene state machine in `process.hpp`: `ProcessID` LOGO -> SYNC -> LOGIN ->
  (CREATEACCOUNT/SELECTCHAR/CREATECHAR/CHANGEPASSWORD) -> RUN. Each process has
  a sibling `*net.cpp` with its network handlers; switches are deferred via
  `requestProcess()`.
- `client/src/client.hpp` `Client::mainLoop()`: poll GLFW/ImGui events -> poll
  `NetIO` (`netio.hpp`, asio TCP, VLQ-framed, timeout-able handlers) ->
  update/draw current `Process`.
- `3rdparty/` holds project ImGui extension headers (`GLTexture.hpp`,
  `ImGuiFileDialog.hpp`); the ImGui GLFW/OpenGL3 backends are compiled from
  sources shipped by the Conan imgui package (wired in `3rdparty/CMakeLists.txt`).

### Lua scripting (sol2)
Two sources: `.lua` files embedded next to classes in `server/src/`
(`player.lua`, `servermap.lua`, `quest.lua`, ...) and the `server/script/` tree
(`api/`, `map/`, `npc/` with shared `npc/include/`, `quest/`, `run/`). C++ binds
functions via `bindFunction()`. The embedded `.lua` files are compiled into the
binary as hex headers by `mir2x_generate_resource()` (see Gotchas).

### Network protocol (common)
Client<->server messages are `#pragma pack(1)` structs: `CMType` + structs in
`common/src/clientmsg.hpp`, `SMType` in `common/src/servermsg.hpp`.
`common/src/msgf.hpp` does head-code/attribute framing (fixed vs variable size,
VLQ lengths, xor/compression). `common/src/serdesmsg.hpp` holds
cereal-serialized payloads (`SDInitPlayer`, `SDSendPackage`, ...) for complex
bodies and peer-to-peer data. Adding a message = new enum value + packed struct
+ handler registration on both ends.

### Storage
Server SQLite DBs (via SQLiteCpp, `server/src/dbpod.hpp`) are **generated at
startup** by `Server::createDefaultDatabase()` — no `.db` files are checked in.
`mir2x.db3` is gitignored.

## Gotchas

- **Do not define `MIR2X_LOG_FILELIST`.** The root CMakeLists auto-collects it
  from `common/`+`client/`+`server/` sources; defining it manually is a
  `FATAL_ERROR`.
- `buildconfig.hpp` and `logprof.hpp` are `configure_file` outputs in
  `<build>/config_file/`. Edit the `.in` templates in `common/src/`, never the
  generated headers.
- Source collection uses plain `file(GLOB)` / `file(GLOB_RECURSE)` **without**
  `CONFIGURE_DEPENDS`. New `.cpp`/`.hpp` files are picked up only after you
  re-run CMake configure (`cmake --fresh --preset conan-default` or just re-run
  the build wrapper).
- `mir2x_generate_resource(target name input)` (root CMakeLists) embeds a
  `.lua`/`.png`/`.ttf` file as a C++ byte-array header. The input is listed in
  `CMAKE_CONFIGURE_DEPENDS`, so editing the source asset triggers regeneration
  on the next configure. Each call adds a generated `<name>.hpp` under
  `<build>/` and exposes it to the target's include path.
- `CMAKE_SKIP_RPATH` is `TRUE`: binaries do not embed runtime library paths.
  When running installed/ported binaries you may need to set `LD_LIBRARY_PATH`
  (Linux) or `PATH` (Windows) to find shared deps.
- The repo has no `.github/` workflow files in this checkout, despite README
  references to GitHub Actions and prebuilt `latest` releases. Don't assume CI
  behavior you can't see here.
