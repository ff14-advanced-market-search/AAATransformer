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
    -- addon.Debug.Log(format("  TSM_API.ToItemString %s", itemLink))
    local tsmItemLink = TSM_API.ToItemString(itemLink)
    if not tsmItemLink then
      -- addon.Debug.Log(format("  Cannot create tsmItemLink for %s, skipping", itemLink))
      return 0
    end
    -- addon.Debug.Log(format("  TSM_API.GetCustomPriceValue() %s %s", priceSource, tsmItemLink))
    return TSM_API.GetCustomPriceValue(priceSource, tsmItemLink)
  end

  return 0
end

function TSM.GetAvailablePriceSources()
  -- addon.Debug.Log("tsm.GetAvailablePriceSources()")

  if not TSM.IsLoaded() then
    -- addon.Debug.Log("tsm.GetAvailablePriceSources: TSM not loaded")
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