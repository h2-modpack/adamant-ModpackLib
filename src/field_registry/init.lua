local internal = AdamantModpackLib_Internal

public.registry = public.registry or {}
public.registry.storage       = public.registry.storage       or {}
public.widgets                = public.widgets                or {}
internal.ui = internal.ui or {}
internal.widgets = internal.widgets or {}

import 'field_registry/internal/ui.lua'
import 'field_registry/storage.lua'
import 'field_registry/internal/widgets.lua'
import 'field_registry/widgets/init.lua'
import 'field_registry/ui.lua'
import 'field_registry/internal/registry.lua'

internal.registry.validateRegistries()
