local addon = select(2, ...)

local TSM = {}
addon.TSM = TSM

-- TSM4
local TSM_API = _G.TSM_API

function TSM.IsLoaded()
  if TSM_API then
    return true
  end
  return false
end

function TSM.GetItemValue(itemLink, priceSource)
  if TSM_API and TSM_API.GetCustomPriceValue then
    local tsmItemLink = TSM_API.ToItemString(itemLink)
    if not tsmItemLink then
      return 0
    end
    return TSM_API.GetCustomPriceValue(priceSource, tsmItemLink)
  end

  return 0
end

function TSM.GetAvailablePriceSources()
  if not TSM.IsLoaded() then
    return
  end

  local priceSources = {}
  local keys = {}

  -- filter
  local tsmPriceSources = {}
  TSM_API.GetPriceSourceKeys(tsmPriceSources)

  -- TSM registers price sources from other addons
  -- so lets filter to only the ones we should
  -- know about
  local validSources = {
    ["DBHistorical"] = true,
    ["DBMarket"] = true,
    ["DBMinBuyout"] = true,
    ["DBRegionHistorical"] = true,
    ["DBRegionMarketAvg"] = true,
    ["DBRegionMinBuyoutAvg"] = true,
    ["DBRegionSaleAvg"] = true,
    ["DBRecent"] = true,
    ["VendorSell"] = true,
  }

  for k, v in pairs(tsmPriceSources) do
    if addon.CONST.PRICE_SOURCE[k] and validSources[k] then
      table.insert(keys, k)
    elseif addon.CONST.PRICE_SOURCE[v] and validSources[v] then
      table.insert(keys, v)
    end
  end


  sort(keys)

  for _, v in ipairs(keys) do
    priceSources[v] = addon.CONST.PRICE_SOURCE[v]
  end

  return priceSources
end

function TSM.GetGroups()
  if not TSM.IsLoaded() then
    return
  end

  local groups = {}

  -- filter
  local tsmGroups = {}
  TSM_API.GetGroupPaths(tsmGroups)

  for k, v in pairs(tsmGroups) do
    table.insert(groups, k, v)
  end

  return groups
end

function TSM.FormatGroupPath(path)
  if not TSM.IsLoaded() then
    return
  end

  return TSM_API.FormatGroupPath(path)
end

function TSM.SplitGroupPath(path)
  if not TSM.IsLoaded() then
    return
  end

  return TSM_API.SplitGroupPath(path)
end

function TSM.GetGroupItems(path, includeSubGroups, result)
  if not TSM.IsLoaded() then
    return
  end

  return TSM_API.GetGroupItems(path, includeSubGroups, result)
end

function TSM.GetItemLink(itemString)
  if not TSM.IsLoaded() then
    return itemString
  end

  return TSM_API.GetItemLink(itemString)
end
