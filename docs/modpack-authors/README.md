# Modpack Author Docs

Use these docs when building or maintaining a pack coordinator on top of
`adamant-ModpackLib.modpack`.

Recommended order:

1. [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
2. [QUICK_SETUP.md](QUICK_SETUP.md)
3. [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)

Module implementation details still live under
[../module-authors/README.md](../module-authors/README.md). Coordinator code
should stay pack-scoped: identity, profiles, module order, GUI registration,
and optional pack quick controls.
