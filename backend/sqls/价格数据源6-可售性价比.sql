/*
文件: 价格数据源6-可售性价比.sql
指标: 车数|可售C2面客价|全国实时模型价|可售C2面客价性价比|可售C1到手价|上架时C2B模型价|可售C1到手价性价比
业务: C1可售的性价比
场景: 分析可售车源的C1到手价性价比和C2面客价性价比
标签：面客|可售|性价比|模型价|C2B模型价|到手价
维度: dt
核心表: dm_user_car_usedcar_tracking_inc_ymd|dw_event_clue_licensed_city_ymd|dim_ctob_auction_car_source_ymd
作者: 文国庆|杨悦芳 
描述: 计算可售车源的C1到手价性价比(可售C1到手价/上架时C2B模型价)和C2面客价性价比(可售C2面客价/全国实时模型价)
*/
-- 可售C1到手价性价比 = 可售C1到手价 / 上架时C2B模型价
-- 可售C2面客价性价比 = 可售C2面客价 / 全国实时模型价
with on_sale as(
    select 
        t1.dt
        ,clue_type
        ,t1.clue_id
        ,cast(sum(receive_price*uv)/sum(uv) as decimal(18,0)) as receive_price -- 可售C2面客价
        ,max(COALESCE(listing_model_price,cur_zhijia_protect_price)) as listing_model_price -- 全国实时模型价
        ,max(platform_price) platform_price -- 可售C1到手价
    from (
        select
            dt
            ,clue_id
            ,user_city_id 
            ,case when sku_type = 4 then 'C2C'
                  when is_golden2 = 1 and (valid_tags like '%1599%' or valid_tags like '%1610%') then '自营' 
                  when is_golden2 = 1 then 'B2C' 
                  else '其他' 
             end as clue_type
            -- ,receive_price + 1000 as receive_price
            ,count(distinct gz_user_id) uv
            ,max(platform_price) as platform_price
            ,max(cur_zhijia_protect_price) as cur_zhijia_protect_price
            ,max(listing_model_price) as listing_model_price
        from guazi_dw_dm.dm_user_car_usedcar_tracking_inc_ymd
        where dt between '${start}' and '${date_y_m_d}'
          and sku_type = 4
          and sku_status_code = 10
          and (fuel_list_feed_beseen_pv > 0 
               or zone_list_feed_beseen_pv > 0 
               or list_feed_car_source_beseen_pv > 0 
               or newenergy_feed_feed_list_beseen_cnt > 0 
               or old_newenergy_feed_feed_list_beseen_cnt > 0)
        group by 1,2,3,4
		
    ) t1
	join 
	 (    
		select 
         clue_id
		-- ,CASE WHEN fuel_type IN (12, 13, 20) THEN '新能源' ELSE '燃油' END as fuel_type
		-- ,case when sku_type = 4 then 'C2C'
		-- when is_self_operated = 1 then '自营'
		-- else 'B2C' end clue_type
		,tag_name
        ,licensed_city_id
        ,receive_price+1000 as receive_price
        ,dt
		from guazi_dw_dw.dw_event_clue_licensed_city_ymd
		where dt between '${start}' AND '${date_y_m_d}'
		and product_status_desc = '上架可售'
	) t2 on t1.clue_id = t2.clue_id and t2.licensed_city_id = t1.user_city_id and t1.dt = t2.dt
    where receive_price > 0 and uv > 0
    group by 1,2,3
)

,all_ as (
    select
        on_sale.dt,
        on_sale.clue_id,
        on_sale.receive_price,           -- 可售C2面客价
        on_sale.listing_model_price,     -- 全国实时模型价
        on_sale.platform_price,          -- 可售C1到手价
        c2b_model_price.seller_model_price, -- 上架时C2B模型价
        -- 先计算每一台车的性价比
        (on_sale.receive_price / on_sale.listing_model_price) as per_car_c2_ratio,      -- 每台车：可售C2面客价性价比
        (on_sale.platform_price / c2b_model_price.seller_model_price) as per_car_c1_ratio -- 每台车：可售C1到手价性价比
    from on_sale
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
    ) c2b_model_price on on_sale.clue_id = c2b_model_price.clue_id
    where on_sale.receive_price > 0 
      and on_sale.listing_model_price > 0 
      and on_sale.platform_price > 0 
      and c2b_model_price.seller_model_price > 0
)

select 
    dt,
    count(distinct clue_id) as `车数`,
    sum(receive_price) / count(distinct clue_id) as `可售C2面客价`,
    sum(listing_model_price) / count(distinct clue_id) as `全国实时模型价`,
    -- 性价比 = 每台车性价比之和 / 车数（等价于 sum(价格比) / count）
    sum(per_car_c2_ratio) / count(distinct clue_id) as `可售C2面客价性价比`,
    sum(platform_price) / count(distinct clue_id) as `可售C1到手价`,
    sum(seller_model_price) / count(distinct clue_id) as `上架时C2B模型价`,
    sum(per_car_c1_ratio) / count(distinct clue_id) as `可售C1到手价性价比`
from all_
group by dt
order by dt