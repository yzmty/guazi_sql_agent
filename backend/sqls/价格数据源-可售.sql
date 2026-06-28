/*
文件: 价格数据源-可售.sql
指标: 车数|C2B预估成交价|模型价|C1到手价|面客价|B2C预估成交价|应收佣金|其他加价|全国实时模型价|C1多卖|平台利润|C2少花1|C2少花2|总利润空间
业务: C1-C2C可售车源
场景: 分析C2C可售车源的价格构成与利润空间，计算C1多卖和C2少花的性价比指标
标签：交车|价格|C2B|B2C|C2C|C1|C2|多卖|少花|C2C成交车源|C2B预估成交价|模型价|成交C1到手价|实付价|B2C预估成交价|应收佣金|其他加价|面客区域模型价|C1多卖|平台利润|C2少花1|C2少花2|总利润空间
维度: 上架日期dt|燃油类型fuel_type|C2B模型价价格段hit_factor_c2b_model_price_range      
核心表: dw_ctob_appoint_prepay_detail_ymd|dw_car_platform_quality_supply_detail_ymd|fact_ctob_consign_price_result_log, dim_platform_clue_cost_performance_level_rule_ymd|dim_ctob_auction_car_source_ymd, dw_usedcar_order_mk_level_ymd|dw_ctob_evaluate_task_ymd, dm_user_car_usedcar_tracking_inc_ymd|rewenlengchexi
作者: 文国庆|杨悦芳
描述: 针对C2C可售的车源分析C2C的C1多卖和C2少花
*/
with 
c2b_model_price AS (
  -- c2b 模型价
  SELECT
    CASE
      WHEN fuel_type IN (12, 13, 20) THEN '新能源'
      ELSE '燃油'
    END as fuel_type,
    case when seller_model_price >= 0 and seller_model_price < 30000 then '3w-'
		when seller_model_price >= 30000 and seller_model_price < 50000 then '3-5w'
		when seller_model_price >= 50000 and seller_model_price < 80000 then '5-8w'
		when seller_model_price >= 80000 and seller_model_price < 120000 then '8-12w'
		when seller_model_price >= 120000 then '12w+'
	else null end price_range,
    tag_id,
    -- 车系
    tag_name,
    -- 车系
	minor_category_name,
	minor_category_id,
    clue_id,
    SUBSTRING(onshelf_time, 1, 10) AS dt,
    seller_model_price
  FROM
    guazi_dw_dwd.dim_ctob_auction_car_source_ymd
  WHERE
    dt = '${date_y_m_d}'
    AND ctob_busi_type_code IN (0, 1, 2)
)
,c2c_deal_price as (
  -- C2C的c1到手价
  SELECT
    substr(prepay_time, 1, 10) prepay_dt,
    clue_id,
    c_order_id,
    prepay_order_id,
    deal_price,
    ctob_deal_busi_code
  FROM
    guazi_dw_dw.dw_ctob_appoint_prepay_detail_ymd
  WHERE
    dt = '${date_y_m_d}'
    and ctob_busi_type_code in (0, 1, 2) -- C1车源
    and ctob_deal_busi_code in (3, 1, 5, 4) -- C2C+C2B+自营C收车成交
    AND substr(prepay_time, 1, 10) BETWEEN date_sub('${date_y_m_d}', 120) AND '${date_y_m_d}'
)
,c2b_fit as (
  -- 已定：c2b 模型价与c2b成交价的拟合系数，中位数逻辑
  SELECT
    fuel_type,
    price_range,
	minor_category_name,
    tag_id,
    tag_name,
    c2b_deal_cnt,
    -- 逻辑处理：如果样本少于3，取同fuel_type和price_range的全局中位数
    CASE
      WHEN c2b_deal_cnt <= 3 THEN percentile_approx(c2b_median_deal_price, 0.5) OVER(PARTITION BY fuel_type, price_range, minor_category_name)
      ELSE c2b_median_deal_price
    END AS final_deal_price,
    CASE
      WHEN c2b_deal_cnt <= 3 THEN percentile_approx(c2b_median_model_price, 0.5) OVER(PARTITION BY fuel_type, price_range, minor_category_name)
      ELSE c2b_median_model_price
    END AS final_model_price,
    (
      CASE
        WHEN c2b_deal_cnt <= 3 THEN percentile_approx(c2b_median_deal_price, 0.5) OVER(PARTITION BY fuel_type, price_range, minor_category_name)
        ELSE c2b_median_deal_price
      END
    ) * 1.00 / (
      CASE
        WHEN c2b_deal_cnt <= 3 THEN percentile_approx(c2b_median_model_price, 0.5) OVER(PARTITION BY fuel_type, price_range, minor_category_name)
        ELSE c2b_median_model_price
      END
    ) as c2b_deal_index
  FROM
    (
      -- 已定：c2b 模型价与c2b成交价的拟合系数，中位数逻辑
      select
        t2.fuel_type,
        t2.price_range,
        t2.tag_id,
        t2.tag_name,
		t2.minor_category_name,
        count(distinct t1.prepay_order_id) c2b_deal_cnt,
        -- c2b成交量
        percentile_approx(t1.deal_price, 0.5) as c2b_median_deal_price,
        -- c2b成交中位数
        percentile_approx(t2.seller_model_price, 0.5) as c2b_median_model_price -- c2b模型价中位数
      FROM
        (
          select
            *
          from
            c2c_deal_price
          where ctob_deal_busi_code in (1, 5) -- C2B成交
            and prepay_dt BETWEEN date_sub('${date_y_m_d}', 120) AND '${date_y_m_d}'
        ) t1 -- 近30天C2B成交
        LEFT join c2b_model_price t2 on t1.clue_id = t2.clue_id
      where
        t2.seller_model_price is not null
      group by 1,2,3,4,5 
    ) t
)
,b2c_fit as (-- b2c成交拟合系数
  -- 已定：b2c 模型价与车主承担价的拟合系数，中位数逻辑
  SELECT
    fuel_type,
    price_range,
    tag_name,
	brand_name,
    b2c_deal_cnt,
    -- 处理车商承担价：若样本 < 3，取同能源类型、同价格带的中位数兜底
    CASE
      WHEN b2c_deal_cnt <= 3 THEN percentile_approx(b2c_median_undertake_price, 0.5) OVER(PARTITION BY fuel_type, price_range,brand_name)
      ELSE b2c_median_undertake_price
    END AS final_undertake_price,
    -- 处理 B2C 模型价：若样本 < 3，取同级别的中位数兜底
    CASE
      WHEN b2c_deal_cnt <= 3 THEN percentile_approx(b2c_median_model_price, 0.5) OVER(PARTITION BY fuel_type, price_range,brand_name)
      ELSE b2c_median_model_price
    END AS final_b2c_model_price,
    -- 计算 B2C 拟合系数 (Index)
    (
      CASE
        WHEN b2c_deal_cnt <= 3 THEN percentile_approx(b2c_median_undertake_price, 0.5) OVER(PARTITION BY fuel_type, price_range,brand_name)
        ELSE b2c_median_undertake_price
      END
    ) * 1.00 / COALESCE(
      (
        CASE
          WHEN b2c_deal_cnt <= 3 THEN percentile_approx(b2c_median_model_price, 0.5) OVER(PARTITION BY fuel_type, price_range,brand_name)
          ELSE b2c_median_model_price
        END
      ),
      0
    ) AS b2c_deal_index
  from
    (
      SELECT
        t1.fuel_type,
        t1.tag_name,
		t1.brand_name,
		case when t3.listing_price >= 0 and t3.listing_price < 30000 then '3w-'
		when t3.listing_price >= 30000 and t3.listing_price < 50000 then '3-5w'
		when t3.listing_price >= 50000 and t3.listing_price < 80000 then '5-8w'
		when t3.listing_price >= 80000 and t3.listing_price < 120000 then '8-12w'
		when t3.listing_price >= 120000 then '12w+'
	else null end price_range,
        count(distinct t1.order_id) b2c_deal_cnt,
        -- b2c成交量
		percentile_approx(t3.customer_price, 0.5) as b2c_median_undertake_price,
        percentile_approx(listing_price, 0.5) as b2c_median_model_price -- b2c全国实时模型价中位数
      FROM
        (
          select
            CASE
              WHEN fuel_type IN (12, 13, 20) THEN '新能源'
              ELSE '燃油'
            END as fuel_type,
            -- 燃油类型
            tag_name,
            -- 车系
			brand_name, -- 品牌
            order_id,
            listing_model_price
          from
            guazi_dw_dw.dw_store_platform_forward_cost_detail_ymd
          where
            dt = '${date_y_m_d}'
            and substr(deliver_car_prepay_time, 1, 10) BETWEEN date_sub('${date_y_m_d}', 180)  -- 120
            AND '${date_y_m_d}'
            and is_cb_sale is null -- 非C2C
            and (
              create_car_source_tags NOT LIKE '%1599%'
              and create_car_source_tags NOT LIKE '%1610%'
            ) -- 非自营
        ) t1
		left join (
			select order_id,customer_price,
			CASE WHEN listing_price > 0 THEN listing_price 
				WHEN cur_zhijia_protect_price > 0 THEN cur_zhijia_protect_price ELSE NULL END listing_price
			from guazi_dw_dw.dw_usedcar_order_mk_level_ymd
			where dt = '${date_y_m_d}'
		) t3 on t1.order_id = t3.order_id
      where t3.listing_price > 0
      group by 1,2,3,4
    ) a
)
,on_sale as (-- C2C曝光过车源
    SELECT
		clue_id,dt,receive_price,listing_model_price,
		case when listing_model_price >= 0 and listing_model_price < 30000 then '3w-'
		when listing_model_price >= 30000 and listing_model_price < 50000 then '3-5w'
		when listing_model_price >= 50000 and listing_model_price < 80000 then '5-8w'
		when listing_model_price >= 80000 and listing_model_price < 120000 then '8-12w'
		when listing_model_price >= 120000 then '12w+'
	else null end listing_model_price_range
	FROM
	(select  
        clue_id
        ,dt
        ,cast(sum(receive_price*uv)/sum(uv) as decimal(18,0)) as receive_price-- 曝光加权的在售面客价（车款+物流费+过户费）
        ,max(COALESCE(listing_model_price,cur_zhijia_protect_price)) as listing_model_price-- 全国实时模型价
    from (
        select
            dt
            ,clue_id
            ,user_city_id 
            ,receive_price + 1000 as receive_price
            ,count(distinct gz_user_id) uv
            ,max(cur_zhijia_protect_price) as cur_zhijia_protect_price
            ,max(listing_model_price) as listing_model_price
        from guazi_dw_dm.dm_user_car_usedcar_tracking_inc_ymd
        where dt BETWEEN date_sub('${start_time}', 60) AND '${date_y_m_d}'
        and sku_type = 4
        and ( fuel_list_feed_beseen_pv > 0 or zone_list_feed_beseen_pv > 0 or list_feed_car_source_beseen_pv > 0 or newenergy_feed_feed_list_beseen_cnt > 0 or old_newenergy_feed_feed_list_beseen_cnt > 0 )
        group by 1,2,3,4
    ) t
    where receive_price > 0 and uv >0 -- 剔除空值
    group by 1,2) t1
	
)
, all_ as (
select 
    t0.dt,
    t0.brand_id,
	t0.brand_name,
    case when t6.is_almost_new_car = '老车' then 1 else 0 end is_old_car,
    t0.tag_id,
    CASE WHEN t5.type IS NOT NULL THEN t5.type ELSE '冷' END AS type,
    t0.fuel_type, -- 修正列歧义
    t0.clue_id,
    hit_factor_c2b_model_price,
	case when hit_factor_c2b_model_price >= 0 and hit_factor_c2b_model_price < 30000 then '3w-'
		when hit_factor_c2b_model_price >= 30000 and hit_factor_c2b_model_price < 50000 then '3-5w'
		when hit_factor_c2b_model_price >= 50000 and hit_factor_c2b_model_price < 80000 then '5-8w'
		when hit_factor_c2b_model_price >= 80000 and hit_factor_c2b_model_price < 120000 then '8-12w'
		when hit_factor_c2b_model_price >= 120000 then '12w+'
	else null end hit_factor_c2b_model_price_range,
    ctb_high_bid_price,
    premium_type,
    premium_value,
    retail_premium,
    raw_c_price,
    upper_limit,
    lower_limit,
    limited_c_price,
    basePrice,
	final_c_price,
    t0.platform_price as `C1到手价`,
    t0.yongjin,
	COALESCE(receive_price,0)-COALESCE(t0.platform_price,0)-COALESCE(t0.yongjin,0) other_price,
    receive_price as `面客价`,
    listing_model_price as `全国实时模型价`,
	listing_model_price_range as `全国实时模型价价格带`,
    btc_s_model_price,
    COALESCE(s_lower_limit,1) s_lower_limit,
    COALESCE(ss_lower_limit,1) ss_lower_limit,
	COALESCE(c2b_deal_index,1) c2b_deal_index,
	COALESCE(b2c_deal_index,1) b2c_deal_index,
	hit_factor_c2b_model_price*COALESCE(c2b_deal_index,1) as `C2B预估成交价`, -- 模型价*C2B成交拟合系数
	listing_model_price*COALESCE(b2c_deal_index,1) as `B2C预估成交价` -- 全国实时模型价*B2C成交拟合系数（同车系B2C成交价/全国实时模型价）
from 
(
-- C2C可售车源
SELECT
	    dt ,-- 上架时间
        clue_id,
        brand_id,
		brand_name,
        tag_id,tag_name,
        CASE WHEN fuel_type IN (12, 13, 20) THEN '新能源' ELSE '燃油' END AS fuel_type,
       -- substr(cb_first_shelf_time,1,10) shelf_date, -- cb同售首次上c时间
        level_rule_id,
        car_id,
        platform_price, -- 当日C1到手价
		cur_zhijia_protect_price, -- 区域保护模型价
        COALESCE(price,0) - COALESCE(djprice,0) -COALESCE(marketing_amount,0) shangpin_price, -- 当日商品价
        COALESCE(price,0) - COALESCE(djprice,0) -COALESCE(marketing_amount,0) - COALESCE(platform_price,0) yongjin -- 佣金
  FROM
    guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
  WHERE dt BETWEEN '${start_time}' AND '${date_y_m_d}' 
  AND sku_type = 4
	and sku_status_code = 10
	-- AND substr(create_time, 1, 10) = dt
) t0
left join 
(-- 寄售上架车源
  SELECT
       clue_id,
        brand_id,
		brand_name,
        tag_id,tag_name,
        CASE WHEN fuel_type IN (12, 13, 20) THEN '新能源' ELSE '燃油' END AS fuel_type,
        substr(cb_first_shelf_time,1,10) shelf_date, -- cb同售首次上c时间
        level_rule_id,
        car_id,
        platform_price, -- 当日C1到手价
		cur_zhijia_protect_price, -- 区域保护模型价
        COALESCE(price,0) - COALESCE(djprice,0) -COALESCE(marketing_amount,0) shangpin_price, -- 当日商品价
        COALESCE(price,0) - COALESCE(djprice,0) -COALESCE(marketing_amount,0) - COALESCE(platform_price,0) yongjin -- 佣金
  FROM
    guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
  WHERE dt BETWEEN date_sub('${date_y_m_d}', 180) AND '${date_y_m_d}'  -- 150
  AND sku_type = 4 AND (valid_tags LIKE '%1564%' OR valid_tags LIKE '%1580%') AND substr(cb_first_shelf_time, 1, 10) = dt
) t1
on t0.clue_id = t1.clue_id
left join 
(-- C1到手价计算过程
SELECT
        dt,
        clue_id,
        car_id,
        btc_s_model_price,
        buyer_bid_price,
        history_bid_percentile,
        ctb_high_bid_price,
        premium_type,
        premium_value,
        retail_premium,
        raw_c_price,
        upper_limit,
        lower_limit,
        limited_c_price,
        final_c_price,
        calc_context_json,
        ext,
        -- 从 calc_context_json 文本中正则提取 C2B 成交模型价
        cast(regexp_extract(calc_context_json, 'C2B成交模型价[:：]\\s*([0-9]+)', 1) as bigint) as hit_factor_c2b_model_price,
		
        -- 从 calc_context_json 文本中正则提取系数
        cast(regexp_extract(calc_context_json, '系数[:：]\\s*([0-9]+)', 1) as bigint) as hit_factor_coef,
        -- Doris使用json_extract替代get_json_object解析JSON
        CAST(json_extract(t.calc_context_json, '$.baseInfo.basePrice') AS BIGINT) AS basePrice,
        cal_price_id AS snapshotCalPriceId,  -- 定价ID快照
        from_unixtime(t.calc_time, 'yyyy-MM-dd HH:mm:ss') AS calc_time_fmt  -- 定价时间（格式化）
    FROM
    (
        SELECT
            *,
            row_number() OVER (
                PARTITION BY clue_id, dt
                ORDER BY calc_time DESC
            ) rn
        FROM gzlc_real.fact_ctob_consign_price_result_log
        WHERE dt BETWEEN '${start_time}' AND '${date_y_m_d}'
          AND calc_status = 0 -- 0：成功，1：失败
          AND calc_type = '实时计算'         -- 实时计算类型
    ) t
    WHERE t.rn = 1
) t2 on t1.clue_id = t2.clue_id and t1.shelf_date = t2.dt
left join
(
    SELECT
        level_rule_id,      -- 等级规则ID
        car_id,             -- 车辆ID
        is_experiments,     -- 是否实验组
        sss_upper_limit,    -- SSS级上限
        sss_lower_limit,    -- SSS级下限
        ss_upper_limit,     -- SS级上限
        ss_lower_limit,     -- SS级下限
        s_upper_limit,      -- S级上限
        s_lower_limit,      -- S级下限
        a_upper_limit,      -- A级上限
        a_lower_limit,      -- A级下限
        b_upper_limit,      -- B级上限
        b_lower_limit,      -- B级下限
        dt                  -- 分区日期
    FROM
    (
        SELECT
            level_rule_id,
            car_id,
            is_experiments,
            sss_upper_limit,
            sss_lower_limit,
            ss_upper_limit,
            ss_lower_limit,
            s_upper_limit,
            s_lower_limit,
            a_upper_limit,
            a_lower_limit,
            b_upper_limit,
            b_lower_limit,
            dt,
            row_number() OVER (
                PARTITION BY dt, car_id, is_experiments, level_rule_id
                ORDER BY update_time DESC       -- 取最新更新的规则
            ) rn
        FROM guazi_dw_dwd.dim_platform_clue_cost_performance_level_rule_ymd
        WHERE dt BETWEEN '2025-11-20' AND '${date_y_m_d}'
    ) x
    WHERE x.rn = 1                              -- 仅保留最新规则
) t4 on t1.shelf_date = t4.dt AND t1.level_rule_id = t4.level_rule_id AND t1.car_id = t4.car_id and is_experiments = 0 AND t4.car_id > 0     -- 排除无效
-- 关联冷热车标签
LEFT JOIN (
    SELECT * 
    FROM guazi_dw_import.rewenlengchexi 
    WHERE dt = '2025-12-29'
) t5 ON t0.tag_id = t5.tag_id
left join -- 关联新能源/准新车标签
(
    SELECT
        clue_id,
        case when road_haul <= 30000 and license_years <= 2 then '准新车'
            when (road_haul > 100000 or license_years > 10) then '老车'
            else '其他' end is_almost_new_car
    FROM guazi_dw_dw.dw_ctob_evaluate_task_ymd
    WHERE dt = '${date_y_m_d}'
      AND ctob_busi_type_code = 1
      AND SUBSTR(onshelf_time, 1, 10) BETWEEN '${start_time}' AND '${date_y_m_d}'
) t6 ON t0.clue_id = t6.clue_id
left join on_sale on t1.clue_id= on_sale.clue_id and t1.shelf_date = on_sale.dt
left join c2b_model_price on t1.clue_id = c2b_model_price.clue_id
left join c2b_fit c2b on t1.fuel_type = c2b.fuel_type and c2b_model_price.price_range = c2b.price_range and t1.tag_id = c2b.tag_id and t1.brand_name = c2b.minor_category_name-- 关联 c2b_fit 以获取 c2b_deal_index
left join b2c_fit b2c on t1.fuel_type =b2c.fuel_type and on_sale.listing_model_price_range= b2c.price_range and t1.tag_name = b2c.tag_name and t1.brand_name = b2c.brand_name-- 关联 b2c_fit 以获取 b2c_deal_index
where 
t2.hit_factor_c2b_model_price > 0-- 剔除空值
and listing_model_price > 0 -- 剔除空值
order by 1
)
select 
dt
,fuel_type
,hit_factor_c2b_model_price_range
,count(distinct clue_id) as `车数`,
    sum(C2B预估成交价) as `C2B预估成交价`,
    sum(hit_factor_c2b_model_price) as `模型价`,
    sum(C1到手价) as `C1到手价`,
    sum(面客价) as `面客价`,
    sum(B2C预估成交价) as `B2C预估成交价`,
    sum(yongjin) as `应收佣金`,
    sum(other_price) as `其他加价`,
    sum(全国实时模型价) as `全国实时模型价`,   
  (sum(C1到手价) - sum(C2B预估成交价))  `C1多卖` ,
 (sum(yongjin) + sum(other_price))    `平台利润` ,
 (sum(B2C预估成交价) - sum(面客价))     `C2少花1`  ,
 (sum(B2C预估成交价) - sum(面客价))    `C2少花2`  , -- 和C2少花1一样只是分母不一样
 sum(B2C预估成交价) - sum(C2B预估成交价)    `总利润空间` 
from all_
group by 1, 2, 3
order by 1, 2, 3