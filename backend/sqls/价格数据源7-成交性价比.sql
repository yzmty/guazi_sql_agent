/*
文件: 价格数据源7-成交性价比.sql
指标: 车数|成交C1到手价|上架时C2B模型价|成交C2实付价|全国实时模型价|成交C1到手价性价比|成交C2实付价性价比
业务: C1-C2C成交车源
场景: 分析C2C成交车源的C1到手价性价比和C2实付价性价比
标签：成交|性价比|模型价|C2B模型价|到手价|实付价
维度: 成交日期prepay_dt
核心表: dw_ctob_c1_tob_toc_appoint_detail_ymd|dm_ctob_clue_detail_transform_csd_inc_ymd|dw_usedcar_order_mk_level_ymd|dim_ctob_auction_car_source_ymd
作者: 文国庆|杨悦芳
描述: 计算C2C成交车源的C1到手价性价比(成交C1到手价/上架时C2B模型价)和C2实付价性价比(成交C2实付价/全国实时模型价)
*/
-- 成交C1到手价性价比 = 成交C1到手价 / 上架时C2B模型价
-- 成交C2实付价性价比 = 成交C2实付价 / 全国实时模型价
select 
    prepay_dt,
    count(distinct clue_id) as `车数`,
    sum(deal_price_deliver) / count(distinct clue_id) as `成交C1到手价`, -- 成交C1到手价
    sum(seller_model_price) / count(distinct clue_id) as `上架时C2B模型价`, -- 上架时C2B模型价
    -- 性价比 = 每台车性价比之和 / 车数
    sum(per_car_c1_ratio) / count(distinct clue_id) as `成交C1到手价性价比`,
    sum(customer_price) / count(distinct clue_id) as `成交C2实付价`, -- 成交C2实付价
    sum(listing_price) / count(distinct clue_id) as `全国实时模型价`, -- 全国实时模型价
    sum(per_car_c2_ratio) / count(distinct clue_id) as `成交C2实付价性价比`
from (
    select
        t.prepay_dt,
        t.clue_id,
        t.c_order_id,
        c2c_fee.deal_price_deliver,                    -- 成交C1到手价
        c2b_model_price.seller_model_price,            -- 上架时C2B模型价
        deal_order_info.customer_price,                -- 成交C2实付价
        deal_order_info.listing_price,                 -- 全国实时模型价
        -- 先计算每一台车的性价比
        (c2c_fee.deal_price_deliver / c2b_model_price.seller_model_price) as per_car_c1_ratio,   -- 每台车：成交C1到手价性价比
        (deal_order_info.customer_price / deal_order_info.listing_price) as per_car_c2_ratio      -- 每台车：成交C2实付价性价比
    from (
        select -- 已定
            distinct
            substr(prepay_time,1,10) as prepay_dt,
            prepay_time,
            clue_id,
            c_order_id,
            ctob_deal_busi_code
        from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
        where dt = '${date_y_m_d}'
          and ctob_busi_type_code in (1) 
          and ctob_deal_busi_code in (-1,3)
          and substr(prepay_time,1,10) between '${start_time}' and '${date_y_m_d}'
    ) t
    -- 关联C2C成交费用表（核心字段来源）
    left join (
        select
            clue_id,
            dt as prepay_dt,
            deal_price_deliver
        from guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd
        where dt between '${start_time}' and '${date_y_m_d}'
          and ctob_busi_type_code in (0,1) -- 一口价线索
          and ctob_deal_busi_code = 3      -- C2C成交
          and deliver_num > 0               -- 已定
    ) c2c_fee on t.clue_id = c2c_fee.clue_id and t.prepay_dt = c2c_fee.prepay_dt
    -- 关联订单信息表（核心字段来源）
    left join (
        select
            order_id,
            customer_price,
            listing_price
        from guazi_dw_dw.dw_usedcar_order_mk_level_ymd
        where dt = '${date_y_m_d}'
    ) deal_order_info on t.c_order_id = deal_order_info.order_id
    -- 关联C2B模型价表（核心字段来源）
    left join (
        select
            clue_id,
            onshelf_time,
            seller_model_price
        from guazi_dw_dwd.dim_ctob_auction_car_source_ymd
        where dt = '${date_y_m_d}'
          and ctob_busi_type_code in (0,1,2)
          and seller_model_price is not null
          and onshelf_time is not null
    ) c2b_model_price on t.clue_id = c2b_model_price.clue_id
    where deal_price_deliver > 0 
      and seller_model_price > 0 
      and customer_price > 0 
      and listing_price > 0
) t
group by prepay_dt
order by prepay_dt