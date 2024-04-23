local addon = select(2, ...)

local CONST = {}
addon.CONST = CONST
CONST.PRICE_SOURCE = {
    -- TSM price sources
    ["DBHistorical"] = "TSM: " .. "Historical Price",
    ["DBMarket"] = "TSM: " .. "Market Value",
    ["DBMinBuyout"] = "TSM: " .. "Minimum Buyout",
    ["DBRegionHistorical"] = "TSM: " .. "Region Historical Price",
    ["DBRegionMarketAvg"] = "TSM: " .. "Region Market Value Avg",
    ["DBRegionMinBuyoutAvg"] = "TSM: " .. "Region Min Buyout Avg",
    ["DBRegionSaleAvg"] = "TSM: " .. "Region Global Sale Average",
    ["DBRecent"] = "TSM: " .. "Recent Market Value",
    ["VendorSell"] = "TSM: " .. "VendorSell",

    -- OE price sources
    ["OERealm"] = "OE: " .. "Realm Price",
    ["OERegion"] = "OE: " .. "Region Price",

    -- AHDB price sources
    ["AHDBMinBid"] = "AHDB: " .. "Minimum Bid",
    ["AHDBMinBuyout"] = "AHDB: " .. "Minimum Buyout",

    -- ATR price sources
    ["ATRMarket"] = "ATR: " .. "Auction Value",
}
