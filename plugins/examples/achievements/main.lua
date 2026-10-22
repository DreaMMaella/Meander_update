-- Достижения (эталон плагина L3B).
--
-- Показывает то, чего квест без плагинов не умеет вовсе: прогрессивные
-- награды, которые переживают перезапуск. Счёт и открытые трофеи лежат в
-- `mnd.storage` под ключом квеста, поэтому «Исследователь» не сбрасывается,
-- если выйти из игры.

local BADGE = 'trophies'
local CASE = 'trophyCase'

local DEFINITIONS = {
  { key = 'firstStep', name = 'Первый шаг', hint = 'Начать этот квест', icon = 'flag' },
  { key = 'collector', name = 'Собиратель', hint = 'Нажать на пять предметов', icon = 'bag' },
  { key = 'explorer', name = 'Исследователь', hint = 'Побывать в пяти сценах', icon = 'map' },
  { key = 'deepDive', name = 'Досмотрел до дна', hint = 'Побывать в десяти сценах', icon = 'eye' },
  { key = 'finale', name = 'До конца', hint = 'Дойти до финала квеста', icon = 'star' },
}

local GOAL_TAPS = 5
local GOAL_PLACES = 5
local GOAL_DEEP = 10

--- Открыт ли кейс: состояние живёт в Lua-состоянии плагина, а не в UI.
local caseOpen = false

local function storageKey(key)
  return 'ach:' .. mnd.questId .. ':' .. key
end

local function unlocked(key)
  return mnd.storage.get(storageKey(key)) == true
end

local function openCount()
  local count = 0
  for _, definition in ipairs(DEFINITIONS) do
    if unlocked(definition.key) then count = count + 1 end
  end
  return count
end

local function definitionOf(key)
  for _, definition in ipairs(DEFINITIONS) do
    if definition.key == key then return definition end
  end
end

--- Открыть трофей: повторный вызов ничего не делает, чтобы тост не дублировался.
local function grant(key)
  if unlocked(key) then return end
  mnd.storage.set(storageKey(key), true)
  local definition = definitionOf(key)
  if definition then
    mnd.ui.toast('Достижение: ' .. definition.name, 2600)
    mnd.log.info('открыт трофей ' .. definition.name)
  end
end

--- Сколько разных нод посетил игрок — список живёт в хранилище.
local function visitedCount(nodeId)
  local visited = mnd.storage.get(storageKey('visited')) or {}
  for _, seen in ipairs(visited) do
    if seen == nodeId then return #visited end
  end
  visited[#visited + 1] = nodeId
  mnd.storage.set(storageKey('visited'), visited)
  return #visited
end

local function tapCount()
  local taps = mnd.storage.get(storageKey('taps')) or 0
  taps = taps + 1
  mnd.storage.set(storageKey('taps'), taps)
  return taps
end

local function caseSpec()
  local children = {
    {
      type = 'row',
      children = {
        { type = 'heading', text = 'Достижения', color = 'white', expand = true },
        { type = 'badge', label = openCount() .. '/' .. #DEFINITIONS, background = 'gold', color = 'black' },
      },
    },
    { type = 'divider', color = '#3A3A46' },
  }
  for _, definition in ipairs(DEFINITIONS) do
    local done = unlocked(definition.key)
    children[#children + 1] = {
      type = 'row',
      gap = 8,
      children = {
        { type = 'icon', icon = definition.icon, color = done and 'gold' or 'gray', size = 20 },
        { type = 'column', expand = true, children = {
          { type = 'text', text = definition.name, color = 'white' },
          { type = 'caption', text = definition.hint, color = 'gray' },
        }},
        { type = 'icon', icon = done and 'check' or 'cross', color = done and 'green' or 'gray', size = 18 },
      },
    }
  end
  children[#children + 1] = {
    type = 'button',
    label = 'Закрыть',
    variant = 'outline',
    color = 'white',
    border = '#3A3A46',
    onPress = 'closeCase',
  }
  return {
    type = 'card',
    align = 'stretch',
    gap = 8,
    background = '#15151B',
    border = '#3A3A46',
    radius = 20,
    padding = 18,
    children = children,
  }
end

local function renderBadge()
  mnd.ui.render('slot:' .. BADGE, {
    type = 'chip',
    label = '★ ' .. openCount() .. '/' .. #DEFINITIONS,
    icon = 'star',
    background = '#22222B',
    color = 'gold',
    onPress = 'openCase',
  })
end

function openCase()
  caseOpen = true
  mnd.ui.render('slot:' .. CASE, caseSpec())
end

function closeCase()
  caseOpen = false
  mnd.ui.close('slot:' .. CASE)
end

function on_quest_start()
  grant('firstStep')
  renderBadge()
end

function on_node_enter(payload)
  local nodeId = mnd.nodeId
  if (nodeId == nil or nodeId == '') and payload then nodeId = payload.node_id end
  if nodeId ~= nil and nodeId ~= '' then
    local places = visitedCount(nodeId)
    if places >= GOAL_PLACES then grant('explorer') end
    if places >= GOAL_DEEP then grant('deepDive') end
  end
  if caseOpen then closeCase() end
  renderBadge()
end

function on_item_press()
  if tapCount() >= GOAL_TAPS then grant('collector') end
  renderBadge()
end

function on_quest_end()
  grant('finale')
  renderBadge()
end
