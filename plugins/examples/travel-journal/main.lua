-- Дорожный журнал (эталон плагина L3B).
--
-- Механика, которой в плеере нет: быстрое перемещение по уже посещённым
-- сценам. Плагин сам решает, что запоминать (хранилище), что показать (слот
-- области drawer) и куда отвести игрока (команда goto_node).

local BUTTON = 'journalButton'
local PAGE = 'journalPage'
local MAX_PLACES = 40

--- Открытая страница — состояние плагина, а не квеста.
local pageOpen = false

local function storageKey()
  return 'places:' .. mnd.questId
end

local function places()
  local list = mnd.storage.get(storageKey())
  if type(list) == 'table' then return list end
  return {}
end

--- Название сцены: квест может задать его переменной `nodeLabel`, иначе
--  показываем id ноды — он у вменяемых квестов читаемый.
local function placeLabel()
  local custom = mnd.vars.get('nodeLabel')
  if type(custom) == 'string' and custom ~= '' then return custom end
  if type(mnd.nodeId) == 'string' and mnd.nodeId ~= '' then return mnd.nodeId end
  return 'неизвестная сцена'
end

local function renderButton()
  mnd.ui.render('slot:' .. BUTTON, {
    type = 'chip',
    label = 'Журнал · ' .. #places() .. ' мест',
    icon = 'book',
    background = '#22222B',
    color = 'white',
    onPress = 'openPage',
  })
end

local function pageSpec()
  local list = places()
  local children = {
    { type = 'heading', text = 'Дорожный журнал', color = 'white' },
    { type = 'caption', text = 'Отсюда можно вернуться в любую открытую сцену.', color = 'gray' },
    { type = 'divider', color = '#3A3A46' },
  }
  if #list == 0 then
    children[#children + 1] = { type = 'caption', text = 'Записей пока нет.', color = 'gray' }
  end
  for index = #list, 1, -1 do
    local place = list[index]
    children[#children + 1] = {
      type = 'row',
      gap = 8,
      children = {
        { type = 'icon', icon = 'map', size = 16, color = 'gray' },
        {
          type = 'column',
          expand = true,
          children = {
            { type = 'text', text = place.label or place.node or '', color = 'white' },
            { type = 'caption', text = 'визитов: ' .. tostring(place.visits or 1), color = 'gray' },
          },
        },
        {
          type = 'button',
          label = 'Вернуться',
          args = place.node or '',
          onPress = 'go',
          variant = 'text',
          color = 'gold',
        },
      },
    }
  end
  children[#children + 1] = {
    type = 'button',
    label = 'Закрыть',
    variant = 'outline',
    color = 'white',
    border = '#3A3A46',
    onPress = 'closePage',
  }
  return {
    type = 'scroll',
    children = {
      {
        type = 'card',
        align = 'stretch',
        gap = 8,
        background = '#15151B',
        border = '#3A3A46',
        radius = 20,
        padding = 18,
        children = children,
      },
    },
  }
end

--- Обработчики нажатий — глобальные: `onPress` в спеке хранит имя функции,
--  и ядро ищет её среди глобалов плагина.
function openPage()
  pageOpen = true
  mnd.ui.render('slot:' .. PAGE, pageSpec())
end

function closePage()
  pageOpen = false
  mnd.ui.close('slot:' .. PAGE)
end

--- `args` кнопки — id ноды; плагин уходит в неё той же командой, что и
--  кнопки самого квеста.
function go(argument)
  if type(argument) ~= 'string' or argument == '' then return end
  closePage()
  mnd.game.go(argument)
end

function on_quest_start()
  renderButton()
end

function on_node_enter()
  local nodeId = mnd.nodeId
  if type(nodeId) ~= 'string' or nodeId == '' then return end
  local list = places()
  local found = false
  for index, place in ipairs(list) do
    if place.node == nodeId then
      place.visits = (tonumber(place.visits) or 1) + 1
      place.label = placeLabel()
      list[index] = place
      found = true
    end
  end
  if not found then
    list[#list + 1] = { node = nodeId, label = placeLabel(), visits = 1 }
    while #list > MAX_PLACES do
      table.remove(list, 1)
    end
  end
  mnd.storage.set(storageKey(), list)
  if pageOpen then openPage() end
  renderButton()
end
