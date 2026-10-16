-- ============================================================
-- MAVEN FUZZY FACTORY: FUNNEL ANALYSIS QUERIES
-- ============================================================
-- Six queries, each answering one business question in order:
-- channel profitability -> device split -> page popularity ->
-- funnel drop-off -> referrer detail -> product performance.
-- ============================================================

USE toy_store;

-- QUERY 1: Which traffic sources and campaigns actually make money?

WITH refund_summary AS (
    -- Refunds need to be rolled up to one row per order before they can be joined onto orders without double-counting.
    SELECT
        r.order_id,
        SUM(r.refund_amount_usd) AS refund_amount
    FROM order_item_refunds r
    GROUP BY r.order_id
)
SELECT 
	s.utm_source AS 'Traffic Source',
    s.utm_campaign AS 'Campaign Type',
    s.utm_content AS 'Ad Version ',
    -- Traffic
    COUNT(DISTINCT s.website_session_id) AS 'Sessions',
    ROUND(COUNT(DISTINCT s.website_session_id) * 100.0 / SUM(COUNT(DISTINCT s.website_session_id)) OVER (), 1) AS 'Session Share %',
    -- Orders
    COUNT(DISTINCT o.order_id) AS 'Orders',
    ROUND(COUNT(DISTINCT o.order_id) * 100.0 / COUNT(DISTINCT s.website_session_id),1) AS 'Conversion Rate %',
    -- Gross Revenue
    ROUND(SUM(o.price_usd), 0) AS 'Gross Revenue',
    -- Refunds
    ROUND(SUM(rs.refund_amount), 0) AS 'Refund Amount',
    -- Net Revenue
    ROUND(SUM(o.price_usd) - SUM(rs.refund_amount), 0) AS 'Net Revenue',
    -- Net Gross Profit
    ROUND(SUM(o.price_usd) - SUM(rs.refund_amount) - SUM(o.cogs_usd), 0) AS 'Net Gross Profit',
    -- Efficiency Metrics
    -- This is the number that actually ranks channels — not
    -- session share, not even conversion rate on its own.
    ROUND((SUM(o.price_usd) - SUM(rs.refund_amount) - SUM(o.cogs_usd)) / COUNT(DISTINCT s.website_session_id),1) AS 'Net Profit / Session'
FROM website_sessions s
LEFT JOIN orders o ON o.website_session_id = s.website_session_id
LEFT JOIN refund_summary rs ON rs.order_id = o.order_id
GROUP BY 1,2,3;


-- --------------------------------------------------------------
-- QUERY 2: Desktop vs. mobile — sessions and conversion, at a glance
-- --------------------------------------------------------------

SELECT 
	device_type AS 'Device Type',
    COUNT(*) AS 'Traffic',
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 0) AS 'Traffic %',
    ROUND(COUNT(DISTINCT o.order_id) * 100.0 / COUNT(DISTINCT s.website_session_id),1) AS 'Conversion Rate %'
FROM website_sessions s
LEFT JOIN orders o ON o.website_session_id = s.website_session_id
GROUP BY device_type;


-- --------------------------------------------------------------
-- QUERY 3: What are people actually looking at?
-- --------------------------------------------------------------

SELECT 
    pageview_url,
    COUNT(*) AS pageviews
FROM website_pageviews
GROUP BY pageview_url
ORDER BY pageviews DESC;


-- --------------------------------------------------------------
-- QUERY 4: Where exactly does the mobile funnel break down?
-- --------------------------------------------------------------

WITH session_funnel AS (
    SELECT
        s.website_session_id,
        s.device_type,
        -- Product Stage
        -- Anyone who viewed the product listing page or any individual product page counts as reaching this stage.
        MAX(CASE
                WHEN p.pageview_url IN ('/products', '/the-original-mr-fuzzy', '/the-forever-love-bear', '/the-birthday-sugar-panda', '/the-hudson-river-mini-bear')
                THEN 1 ELSE 0 
			END) AS reached_product,
        MAX(CASE WHEN p.pageview_url = '/cart' THEN 1 ELSE 0 END) AS reached_cart, -- Cart Stage
        MAX(CASE WHEN p.pageview_url = '/shipping'THEN 1 ELSE 0 END) AS reached_shipping, -- Shipping Stage
        MAX(CASE WHEN p.pageview_url IN ('/billing', '/billing-2') THEN 1 ELSE 0 END) AS reached_billing,  -- Billing Stage
        MAX(CASE WHEN o.order_id IS NOT NULL THEN 1 ELSE 0 END) AS placed_order -- Order Stage
    FROM website_sessions s
    LEFT JOIN website_pageviews p
		ON s.website_session_id = p.website_session_id
    LEFT JOIN orders o
        ON s.website_session_id = o.website_session_id
    GROUP BY 1,2
)
SELECT
    device_type AS 'Device',
    COUNT(*) AS 'Sessions',
    -- Product
    -- Formatting as "count (percent)" so each stage is readable on its own without needing to cross-reference total sessions.
   concat(SUM(reached_product), ' (',
    ROUND(SUM(reached_product) * 100.0 / COUNT(*), 1), '%)') AS 'Product Visitors',
    -- Cart
    concat(SUM(reached_cart) , ' (',
    ROUND(SUM(reached_cart) * 100.0 / COUNT(*), 1), '%)') AS 'Cart Visitors',
    -- Shipping
    concat(SUM(reached_shipping) , ' (',
    ROUND(SUM(reached_shipping) * 100.0 / COUNT(*), 1), '%)') AS 'Shipping Visitors',
    -- Billing
    concat(SUM(reached_billing) , ' (',
    ROUND(SUM(reached_billing) * 100.0 / COUNT(*),1), '%)') AS 'Billing Visitors',
    -- Orders
    SUM(placed_order) AS 'Orders',
    ROUND(SUM(placed_order) * 100.0 / COUNT(*), 1) AS 'Conversion Rate %'
FROM session_funnel
GROUP BY device_type;


-- --------------------------------------------------------------
-- QUERY 5: Who's actually sending this traffic?
-- --------------------------------------------------------------

SELECT 
	http_referer,
    COUNT(*) AS session_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM website_sessions
GROUP BY 1;


-- --------------------------------------------------------------
-- QUERY 6: Which products are actually carrying the business?
-- --------------------------------------------------------------

WITH refund_summary AS (
    SELECT
        r.order_id,
        SUM(r.refund_amount_usd) AS refund_amount
    FROM order_item_refunds r
    GROUP BY r.order_id
)
SELECT 
	o.product_id,
    product_name,
    round(sum(price_usd), 0) AS 'Revenue',
    ROUND(SUM(o.price_usd) - SUM(rs.refund_amount) - SUM(o.cogs_usd), 0) AS 'Net Gross Profit',
    ROUND((SUM(o.price_usd) - SUM(rs.refund_amount) - SUM(o.cogs_usd)) / COUNT(o.product_id),1) AS 'Net Gross Profit %',
    ROUND(SUM(rs.refund_amount) * 100.0/ SUM(o.price_usd), 1) AS 'Refund Rate %'
FROM order_items o
LEFT JOIN products p ON p.product_id = o.product_id
LEFT JOIN refund_summary rs ON rs.order_id = o.order_id
GROUP BY 1,2;


-- --------------------------------------------------------------
-- BONUS: Monthly revenue by product, side by side
-- --------------------------------------------------------------

SELECT 
    year(o.created_at) AS 'Year',
    month(o.created_at) AS 'Month',
    ROUND(SUM(CASE WHEN product_id = 1 THEN price_usd ELSE NULL END), 0) AS 'Mr. Fuzzy Revenue',
    ROUND(SUM(CASE WHEN product_id = 2 THEN price_usd ELSE NULL END), 0) AS 'Love Bear Revenue',
    ROUND(SUM(CASE WHEN product_id = 3 THEN price_usd ELSE NULL END), 0) AS 'Sugar Panda Revenue',
    ROUND(SUM(CASE WHEN product_id = 4 THEN price_usd ELSE NULL END), 0) AS 'Mini Bear Revenue',
    round(sum(price_usd), 0) AS 'Revenue',
    ROUND(SUM(o.price_usd) - SUM(o.cogs_usd), 0) AS 'Net Gross Profit'
    -- ROUND((SUM(o.price_usd) - SUM(rs.refund_amount) - SUM(o.cogs_usd)) / COUNT(o.product_id),1) AS 'Net Gross Profit %',
    -- ROUND(SUM(rs.refund_amount) * 100.0/ SUM(o.price_usd), 1) AS 'Refund Rate %'
FROM orders o
LEFT JOIN products p ON p.product_id = o.primary_product_id
GROUP BY 1,2;