-- Инвентарь (эталон плагина L3B).
--
-- Подсистема, которой в движке нет: в квесте можно было показать предмет, но
-- нельзя было носить его с собой. Здесь — механика целиком: предмет в сцене
-- подбирается тапом, кладётся в сетку инвентаря, осматривается, «используется»
-- и выбрасывается.
--
-- Главный приём — рюкзак живёт в ПЕРЕМЕННОЙ КВЕСТА (`bag_items`), а не внутри
-- плагина. Отсюда три следствия:
--   * сетка на сцене привязана к переменной (`items = '{bag_items}'`) и
--     перестраивается клиентом сама — обычный блок «установить переменную»
--     выдаёт игроку предмет без единого вызова плагина;
--   * прогресс попадает в сохранение квеста и в отладочный список переменных;
--   * условие двери проверяет `bag_used_flashlight` — флаг, который плагин
--     заводит при «использовании».
--
-- Второй приём — адаптивность: `cellWidth` задаёт минимальную ширину ячейки, а
-- число колонок клиент считает сам под доступную ширину. В узком слоте это две
-- колонки на телефоне, в экране-перехвате на планшете — пять.

local BAG_VAR = 'bag_items'
local CAP_VAR = 'bag_cap'
local COUNT_VAR = 'bag_count'
local HUD = 'slot:hud'
local INSPECT = 'slot:inspect'
local BAG_SCREEN = 'screen'
local DEFAULT_CAPACITY = 8
local DEFAULT_CELL_WIDTH = 104
local MAX_STACK = 99

--- Обложки: три готовых палитры. Ключи — ровно значения опции `skin`.
local SKINS = {
  ['тёмная'] = { panel = '#15151B', edge = '#3A3A46', cell = '#22222B', accent = 'gold' },
  ['золотая'] = { panel = '#1D1A12', edge = '#6B5423', cell = '#2A2417', accent = 'yellow' },
  ['лесная'] = { panel = '#131C16', edge = '#2F5B3B', cell = '#1B2A20', accent = 'green' },
}

--- Открытые перехваты — состояние сеанса, а не квеста: после перезапуска
--  приложения они закрыты, и это правильно.
local screenOpen = false
local inspectOpen = false

-- ---- мелочи ---------------------------------------------------------------

local function trimmed(value)
  if type(value) ~= 'string' then return '' end
  return value:match('^%s*(.-)%s*$')
end

--- Имя переменной обязано быть ASCII-идентификатором: id айтема — uuid, а
--  ключь предмета автор мог написать и по-русски.
local function slug(value)
  return (string.gsub(tostring(value), '[^%w_]', '_'))
end

local function contains(text, needle)
  return string.find(text, needle, 1, true) ~= nil
end

local function countLabel(name, count)
  local quantity = tonumber(count)
  if quantity ~= nil and quantity > 1 then return name .. ' ×' .. quantity end
  return name
end

-- ---- хранение настроек ----------------------------------------------------

--- Ключи хранилища с префиксом квеста: хранилище плагина одно на приложение.
local function configKey(itemId)
  return 'cfg:' .. mnd.questId .. ':' .. itemId
end

local function lookKey()
  return 'look:' .. mnd.questId
end

local function storedConfig(itemId)
  local cfg = mnd.storage.get(configKey(itemId))
  if type(cfg) == 'table' then return cfg end
  return nil
end

--- Виден ли инвентарь в этом квесте: появляется вместе с первой панелью и
--  помнится между запусками, поэтому счётчик в углу не обязан ждать сцены с
--  панелью.
local function hasBag()
  return type(mnd.storage.get(lookKey())) == 'table'
end

--- Вид рюкзака. Пишется при раскрытии любой панели: панелью правит автор
--  квеста, а HUD и экран-перехват общие на весь квест.
local function lookConfig()
  local stored = mnd.storage.get(lookKey())
  local cfg = type(stored) == 'table' and stored or {}
  local title = trimmed(cfg.title)
  cfg.title = title ~= '' and title or 'Рюкзак'
  if SKINS[trimmed(cfg.skin)] == nil then cfg.skin = 'тёмная' end
  local cell = math.floor(tonumber(cfg.cell) or DEFAULT_CELL_WIDTH)
  cfg.cell = cell < 48 and 48 or cell
  cfg.hud = cfg.hud ~= false and cfg.hud ~= 'false'
  return cfg
end

local function colors()
  return SKINS[lookConfig().skin]
end

-- ---- типы контента --------------------------------------------------------

--- Наш ли айтем и какой именно: `pluginTypeId` — полное имя `<pluginId>:<тип>`
--  из манифеста, его пишет редактор.
local function kindOf(item)
  if type(item) ~= 'table' or item.type ~= 'plugin' then return nil end
  local typeId = trimmed(item.pluginTypeId)
  if contains(typeId, 'inventory') then return 'inventory' end
  if contains(typeId, 'pickup') then return 'pickup' end
  return nil
end

--- Настройки панели из формы. Всё может приехать пустым, число — строкой, а
--  `bool` — словом: редактор хранит то, что ввёл автор.
local function panelConfig(item)
  local data = type(item.pluginData) == 'table' and item.pluginData or {}
  local skin = trimmed(data.skin)
  if SKINS[skin] == nil then skin = 'тёмная' end
  local title = trimmed(data.title)
  local cell = math.floor(tonumber(data.cellWidth) or DEFAULT_CELL_WIDTH)
  if cell < 48 then cell = 48 end
  if cell > 240 then cell = 240 end
  local capacity = math.floor(tonumber(data.capacity) or DEFAULT_CAPACITY)
  if capacity < 1 then capacity = 1 end
  if capacity > 24 then capacity = 24 end
  return {
    kind = 'inventory',
    title = title ~= '' and title or 'Рюкзак',
    capacity = capacity,
    cell = cell,
    skin = skin,
    hud = data.showHud ~= false and data.showHud ~= 'false',
  }
end

local function pickupConfig(item, itemId)
  local data = type(item.pluginData) == 'table' and item.pluginData or {}
  local name = trimmed(data.name)
  local icon = trimmed(data.icon)
  if icon == '' then icon = 'key' end
  local key = trimmed(data.itemKey)
  if key == '' then key = itemId end
  local count = math.floor(tonumber(data.count) or 1)
  if count < 1 then count = 1 end
  if count > MAX_STACK then count = MAX_STACK end
  return {
    kind = 'pickup',
    name = name ~= '' and name or 'Предмет',
    icon = icon,
    key = slug(key),
    count = count,
    picture = trimmed(data.picture),
    description = trimmed(data.description),
    sound = trimmed(data.sound),
    vanish = data.vanish ~= false and data.vanish ~= 'false',
  }
end

-- ---- рюкзак как данные квеста ---------------------------------------------

local function bag()
  local list = mnd.vars.get(BAG_VAR)
  if type(list) == 'table' then return list end
  return {}
end

--- Число мест, занятых предметами: стопка (`count = 3`) занимает одно.
local function sizeOf(list)
  local size = 0
  for _ in ipairs(list) do size = size + 1 end
  return size
end

local function bagSize()
  return sizeOf(bag())
end

local function capacity()
  local stored = math.floor(tonumber(mnd.vars.get(CAP_VAR)) or DEFAULT_CAPACITY)
  if stored < 1 then return 1 end
  return stored
end

local function indexOf(list, key)
  for index, entry in ipairs(list) do
    if type(entry) == 'table' and trimmed(entry.key) == key then return index end
  end
  return nil
end

--- Единственная точка записи рюкзака: счётчик пересчитывается здесь же, чтобы
--  бейдж и полоска на поверхности не расходились с содержимым.
local function saveBag(list)
  mnd.vars.set(BAG_VAR, list)
  mnd.vars.set(COUNT_VAR, sizeOf(list))
end

local function isPicked(key)
  return mnd.vars.get('bag_has_' .. key) == true
end

local function playSound(asset)
  if asset ~= nil and asset ~= '' then mnd.audio.play(asset, 0.8) end
end

-- ---- спеки ----------------------------------------------------------------

--- Ячейка сетки. `args = '{key}'` подставляется значением из элемента: без
--  подстановки все ячейки звали бы `examine` с одним и тем же аргументом.
local function cellTemplate()
  local paint = colors()
  return {
    type = 'button',
    variant = 'outline',
    label = '{name}',
    icon = '{icon}',
    args = '{key}',
    onPress = 'examine',
    color = 'white',
    background = paint.cell,
    border = paint.edge,
    radius = 14,
  }
end

--- Сетка инвентаря. Содержимого в спеке нет намеренно: `items` — это имя
--  переменной, и клиент перестраивает сетку, когда `bag_items` меняется —
--  пусть даже записал её скрипт квеста, а не плагин.
local function bagGrid()
  return {
    type = 'grid',
    items = '{' .. BAG_VAR .. '}',
    columns = 5,
    cellWidth = lookConfig().cell,
    gap = 8,
    ratio = 0.72,
    row = cellTemplate(),
  }
end

--- Заголовок: название, полоска заполненности и счётчик — всё привязано к
--  переменным, ни одной перерисовки ради цифр.
local function bagHeader(title)
  local paint = colors()
  return {
    type = 'column',
    expand = true,
    gap = 8,
    children = {
      {
        type = 'row',
        justify = 'space',
        expand = true,
        children = {
          {
            type = 'row',
            gap = 8,
            children = {
              { type = 'icon', icon = 'bag', color = paint.accent, size = 18 },
              { type = 'text', text = title, color = 'white', bold = true },
            },
          },
          {
            type = 'badge',
            label = '{' .. COUNT_VAR .. '} / {' .. CAP_VAR .. '}',
            color = 'white',
            background = paint.cell,
          },
        },
      },
      {
        type = 'progress',
        value = '{' .. COUNT_VAR .. '}',
        max = '{' .. CAP_VAR .. '}',
        color = paint.accent,
        background = paint.cell,
        height = 6,
        radius = 4,
      },
    },
  }
end

local function panelSpec(cfg)
  local paint = colors()
  return {
    type = 'card',
    align = 'stretch',
    gap = 10,
    background = paint.panel,
    border = paint.edge,
    radius = 18,
    padding = 14,
    children = {
      bagHeader(cfg.title),
      bagGrid(),
      {
        type = 'caption',
        text = 'Тап по ячейке — осмотреть, тап по предмету в сцене — подобрать.',
        color = 'gray',
      },
    },
  }
end

--- Кнопка предмета в сцене. `args` — id айтема: под ним лежит конфиг, и им же
--  различаются сколько угодно предметов на одной ноде.
local function pickupSpec(itemId, cfg)
  local paint = colors()
  return {
    type = 'button',
    variant = 'outline',
    label = countLabel(cfg.name, cfg.count),
    icon = cfg.icon,
    args = itemId,
    onPress = 'collect',
    color = 'white',
    background = '#1B1B22',
    border = paint.edge,
    radius = 999,
    padding = 6,
  }
end

--- Уже подобранный предмет, если автор не просил его прятать.
local function pickedSpec(cfg)
  return {
    type = 'chip',
    label = cfg.name .. ' · в рюкзаке',
    icon = 'check',
    background = '#16221A',
    color = 'gray',
  }
end

--- Карточка предмета в `overlay`-слоте: ширину слота ограничивает клиент,
--  поэтому `width` здесь не нужен.
local function inspectSpec(entry)
  local paint = colors()
  local picture = trimmed(entry.pic)
  local description = trimmed(entry.desc)
  local children = {
    {
      type = 'row',
      gap = 8,
      children = {
        { type = 'icon', icon = trimmed(entry.icon), color = paint.accent, size = 22 },
        {
          type = 'text',
          text = countLabel(trimmed(entry.name), tonumber(entry.count)),
          color = 'white',
          bold = true,
        },
      },
    },
  }
  if picture ~= '' then
    children[#children + 1] = {
      type = 'image',
      src = picture,
      height = 140,
      fit = 'contain',
      radius = 12,
    }
  end
  if description ~= '' then
    children[#children + 1] = {
      type = 'caption',
      text = description,
      color = 'gray',
      maxLines = 6,
    }
  end
  children[#children + 1] = { type = 'divider', color = paint.edge }
  children[#children + 1] = {
    type = 'row',
    justify = 'space',
    gap = 6,
    children = {
      {
        type = 'button',
        label = 'Использовать',
        icon = 'eye',
        args = entry.key,
        onPress = 'useItem',
        color = 'white',
        background = paint.cell,
        border = paint.edge,
      },
      {
        type = 'button',
        label = 'Выбросить',
        args = entry.key,
        onPress = 'dropItem',
        variant = 'text',
        color = 'red',
      },
      {
        type = 'button',
        label = 'Закрыть',
        onPress = 'closeInspect',
        variant = 'text',
        color = 'gray',
      },
    },
  }
  return {
    type = 'card',
    align = 'stretch',
    gap = 8,
    background = paint.panel,
    border = paint.edge,
    radius = 18,
    padding = 16,
    children = children,
  }
end

--- Рюкзак на весь экран — та же сетка, привязанная к тем же переменным.
local function bagScreenSpec(cfg)
  local paint = colors()
  return {
    type = 'scroll',
    children = {
      {
        type = 'card',
        align = 'stretch',
        gap = 12,
        background = paint.panel,
        border = paint.edge,
        radius = 20,
        padding = 16,
        children = {
          bagHeader(cfg.title),
          bagGrid(),
          {
            type = 'button',
            label = 'Закрыть рюкзак',
            variant = 'outline',
            color = 'white',
            border = paint.edge,
            onPress = 'closeBag',
          },
        },
      },
    },
  }
end

-- ---- поверхности ----------------------------------------------------------

local function renderHud()
  if not hasBag() then return end
  local cfg = lookConfig()
  if not cfg.hud then
    mnd.ui.close(HUD)
    return
  end
  mnd.ui.render(HUD, {
    type = 'chip',
    label = cfg.title .. ' · {' .. COUNT_VAR .. '}',
    icon = 'bag',
    background = '#22222B',
    color = 'white',
    onPress = 'openBag',
  })
end

local function renderPickup(itemId, cfg)
  if isPicked(cfg.key) then
    if cfg.vanish then
      mnd.ui.close('item:' .. itemId)
    else
      mnd.ui.render('item:' .. itemId, pickedSpec(cfg))
    end
    return
  end
  mnd.ui.render('item:' .. itemId, pickupSpec(itemId, cfg))
end

-- ---- обработчики кнопок (глобальные: onPress хранит имя функции) ----------

function openBag()
  if not hasBag() then return end
  screenOpen = true
  mnd.ui.render(BAG_SCREEN, bagScreenSpec(lookConfig()))
end

function closeBag()
  screenOpen = false
  mnd.ui.close(BAG_SCREEN)
end

function closeInspect()
  inspectOpen = false
  mnd.ui.close(INSPECT)
end

--- Тап по ячейке. Аргумент — ключ предмета из `bag_items`, поэтому кнопка
--  находит предмет даже тогда, когда сетку собрала переменная, записанная
--  блоком скрипта, а не этим плагином.
function examine(argument)
  local key = slug(trimmed(argument))
  if key == '' then return end
  local list = bag()
  local index = indexOf(list, key)
  if index == nil or type(list[index]) ~= 'table' then
    closeInspect()
    return
  end
  inspectOpen = true
  mnd.ui.render(INSPECT, inspectSpec(list[index]))
end

--- Тап по предмету в сцене: предмет переезжает в рюкзак. Флаг
--  `bag_has_<ключ>` — подарок автору квеста: на него вешается условие видимости
--  двери без всякого плагина.
function collect(argument)
  local itemId = trimmed(argument)
  if itemId == '' then return end
  local cfg = storedConfig(itemId)
  if cfg == nil or cfg.kind ~= 'pickup' then
    mnd.log.warn('инвентарь: предмет ' .. itemId .. ' не настроен — нет данных после item_reveal')
    return
  end
  if isPicked(cfg.key) then
    mnd.ui.toast(cfg.name .. ' уже в рюкзаке', 1200)
    renderPickup(itemId, cfg)
    return
  end
  local list = bag()
  if bagSize() >= capacity() then
    mnd.ui.toast('В рюкзаке нет места: ' .. bagSize() .. ' из ' .. capacity(), 1600)
    return
  end
  list[#list + 1] = {
    key = cfg.key,
    name = cfg.name,
    icon = cfg.icon,
    count = cfg.count,
    pic = cfg.picture,
    desc = cfg.description,
    sound = cfg.sound,
  }
  saveBag(list)
  mnd.vars.set('bag_has_' .. cfg.key, true)
  mnd.ui.toast(cfg.name .. ' — в рюкзаке', 1400)
  playSound(cfg.sound)
  mnd.emit('custom.itemPicked', { key = cfg.key, name = cfg.name })
  renderPickup(itemId, cfg)
end

--- «Использовать» ничего не потребляет: оно оставляет след в квесте. Дальше
--  решает автор — условие `bag_used_flashlight` или блок скрипта.
function useItem(argument)
  local key = slug(trimmed(argument))
  local list = bag()
  local index = indexOf(list, key)
  if index == nil then
    closeInspect()
    return
  end
  local entry = list[index]
  mnd.vars.set('bag_used_' .. key, true)
  mnd.ui.toast(countLabel(trimmed(entry.name), tonumber(entry.count)) .. ': готово', 1400)
  playSound(trimmed(entry.sound))
  mnd.emit('custom.itemUsed', { key = key, name = trimmed(entry.name) })
  if inspectOpen then mnd.ui.render(INSPECT, inspectSpec(entry)) end
end

function dropItem(argument)
  local key = slug(trimmed(argument))
  local list = bag()
  local index = indexOf(list, key)
  if index == nil then
    closeInspect()
    return
  end
  local name = trimmed(list[index].name)
  table.remove(list, index)
  saveBag(list)
  mnd.vars.set('bag_has_' .. key, false)
  mnd.vars.set('bag_used_' .. key, false)
  closeInspect()
  mnd.ui.toast(name .. ' выброшен', 1400)
  mnd.emit('custom.itemDropped', { key = key, name = name })
end

-- ---- события --------------------------------------------------------------

function on_quest_start()
  if mnd.vars.get(CAP_VAR) == nil then mnd.vars.set(CAP_VAR, DEFAULT_CAPACITY) end
  saveBag(bag())
  renderHud()
end

--- Карточка предмета — surface области, он переживает переход между сценами.
--  Снимаем его сами: иначе «Использовать» повиснет на новой ноде.
function on_node_enter()
  if inspectOpen then closeInspect() end
  if screenOpen then openBag() end
  renderHud()
end

function on_item_reveal(payload)
  if type(payload) ~= 'table' then return end
  local item = payload.item_json
  local kind = kindOf(item)
  if kind == nil then return end
  local itemId = item.id or payload.item_id or ''
  if itemId == '' then return end

  if kind == 'inventory' then
    local cfg = panelConfig(item)
    mnd.storage.set(configKey(itemId), cfg)
    mnd.storage.set(lookKey(), cfg)
    mnd.vars.set(CAP_VAR, cfg.capacity)
    saveBag(bag())
    mnd.ui.render('item:' .. itemId, panelSpec(cfg))
    renderHud()
    return
  end

  local cfg = pickupConfig(item, itemId)
  mnd.storage.set(configKey(itemId), cfg)
  renderPickup(itemId, cfg)
end

--- Surface'ы айтемов живут ровно одну сцену: тап по айтему возвращает ему
--  кнопку (или панель), даже если `item_reveal` на эту сцену уже прошёл.
function on_item_press(payload)
  if type(payload) ~= 'table' then return end
  local itemId = payload.item_id or ''
  if itemId == '' then return end
  local cfg = storedConfig(itemId)
  if cfg == nil then return end
  if cfg.kind == 'inventory' then
    mnd.ui.render('item:' .. itemId, panelSpec(cfg))
  elseif cfg.kind == 'pickup' then
    renderPickup(itemId, cfg)
  end
end
