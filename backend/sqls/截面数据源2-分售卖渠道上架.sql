/*
文件: 截面数据源2-分售卖渠道上架.sql
指标: 上架量auction_num|已定量deliver_num|在售量sell_status_num|停售量stop_sell_num
业务: C1车源截面数据（分售卖渠道）
场景: 分析C1车源按上架渠道维度的截面数据，包括上架量、已定量、在售量、停售量等指标，用于监控各渠道车源供给情况
标签: 截面|上架渠道|上架量|已定量|在售量|停售量|C1|自营|C2C|C2B|收车|上架
维度: 上架渠道|组合|dt|B/C收车/C线索ctob_busi_type_code|cb_sale_type|燃油类型fuel_type|价格带model_price_region|宽价格带model_price_region_wide|是否回流is_once_reflow
核心表: dim_com_car_clue_ymd|dim_ctob_auction_car_source_ymd|dw_car_platform_quality_supply_detail_ymd|dw_ctob_auction_car_source_statistic_ymd|dw_ctob_c1_car_source_ymd
作者: 未知
描述: 基于C1链路多表关联生成分售卖渠道的截面数据源，包括上架量、已定量、在售量、停售量等指标，按渠道、燃油类型、价格段等维度汇总
*/
--- 截面数据源2:分渠道截面上架量
with  car_source as 
(
     select 
          a.clue_id
          ,a.city_id
          ,a.ctob_busi_type_code -- 拍卖业务类型码
          ,b.road_haul -- 行驶里程
          ,b.fuel_type -- 燃油类型
          ,b.minor_category_name -- 品牌名称
          ,b.tag_name -- 车系名称
          ,b.title -- 车源标题
          ,b.model_price_region  -- 价格段
		  ,b.model_price_region_wide -- 宽价格段
          ,b.evaluate_level -- 评估师给出的等级
          ,b.transfer_num -- 过户次数（车主 ）
          ,c.city_name
          ,c.province_short_name -- 省份名称
     from 
     (-- 线索明细
          select  
               clue_id  -- 线索 ID
               ,city_id 
               ,ctob_busi_type_code -- 拍卖业务类型码
          from guazi_dw_dwd.dim_com_car_clue_ymd -- 车源线索表
          where dt = date_sub(substring(now(),1,10),1 )   -- 获取前一天的日期：昨天-1天 
		  and (ctob_busi_type_code!=0 or  is_valid!=0) -- 拍卖业务类型码0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车；是否有效线索（C1端业务是否统计为标准）1是0否
          and ctob_busi_type_code in (1,9,10) -- 9B收车 10C收车
     )a 
     left join 
     (   -- 车源维度
          select 
               clue_id  -- 线索 ID
               ,case when road_haul>0 and road_haul<=30000 then 'a.(0-3万]'  -- 	行驶里程
                    when road_haul>30000 and road_haul<=60000 then 'b.(3-6万]'
                    when road_haul>60000 and road_haul<=100000 then 'c.(6-10万]'
                    when road_haul>100000 and road_haul<=150000 then 'd.(10-15万]'
                    when road_haul>150000 and road_haul<=200000 then 'e.(15-20万]'
                    when road_haul>200000 then 'f.20万以上' end as road_haul
               ,if(fuel_type in (12,13,20),'新能源','燃油车') as fuel_type
               ,minor_category_name -- 品牌名称
               ,tag_name -- 车系名称
               ,title -- 车源标题
               ,case
                    when (seller_model_price * 1.0 / 10000) > 0   and (seller_model_price * 1.0 / 10000) <= 1   then 'a.(0-1]' -- 车主上架时模型价(剔除服务费)
                    when (seller_model_price * 1.0 / 10000) > 1   and (seller_model_price * 1.0 / 10000) <= 2   then 'b.(1-2]'
                    when (seller_model_price * 1.0 / 10000) > 2   and (seller_model_price * 1.0 / 10000) <= 4   then 'c.(2-4]'
                    when (seller_model_price * 1.0 / 10000) > 4   and (seller_model_price * 1.0 / 10000) <= 6.5 then 'd.(4-6.5]'
                    when (seller_model_price * 1.0 / 10000) > 6.5 and (seller_model_price * 1.0 / 10000) <= 10  then 'e.(6.5-10]'
                    when (seller_model_price * 1.0 / 10000) > 10  and (seller_model_price * 1.0 / 10000) <= 15  then 'f.(10-15]'
                    when (seller_model_price * 1.0 / 10000) > 15  and (seller_model_price * 1.0 / 10000) <= 20  then 'g.(15-20]'
                    when (seller_model_price * 1.0 / 10000) > 20  and (seller_model_price * 1.0 / 10000) <= 30  then 'h.(20-30]'
                    when (seller_model_price * 1.0 / 10000) > 30  and (seller_model_price * 1.0 / 10000) <= 50  then 'i.(30-50]'
                    when (seller_model_price * 1.0 / 10000) > 50                                                then 'j.(50+)'
               end model_price_region
			   -- 宽价格段
			   ,case
					when (seller_model_price * 1.0 / 10000) > 0  and (seller_model_price * 1.0 / 10000) <= 4 then '(0-4]'
					when (seller_model_price * 1.0 / 10000) > 4 and (seller_model_price * 1.0 / 10000) <= 10 then '(4-10]'
					when (seller_model_price * 1.0 / 10000) > 10 and (seller_model_price * 1.0 / 10000) <= 15 then '(10-15]'
					when (seller_model_price * 1.0 / 10000) > 15 and (seller_model_price * 1.0 / 10000) <= 20 then '(15-20]'
					when (seller_model_price * 1.0 / 10000) > 20 then '(20+)'
				end model_price_region_wide
               ,evaluate_level -- 评估师给出的等级
               ,case when transfer_num<3 then cast(transfer_num as string) else '3次及以上' end transfer_num  -- 过户次数（车主 ）
                    
          from guazi_dw_dwd.dim_ctob_auction_car_source_ymd -- B端车源信息维表
          where dt =date_sub(substring(now(),1,10),1 )    -- 昨天
     )b on a.clue_id =b.clue_id
     left join 
     (-- 车源城市维度
          select
          city_id 
          ,city_name
          ,province_short_name -- 省份名称
          from guazi_dw_dwd.dim_com_city_ymd -- 城市维表
          where dt = date_sub(substring(now(),1,10),1 )
     )c on c.city_id=a.city_id 
)
,car_source_sell_status as 
(-- 车源销售状态
     select 
          dt 
          ,clue_id 
          ,case when sell_status=0 then 1 else 0 end is_sell_status_0 -- 售出状态0/1
          ,case when sell_status=3 and substr(stop_sale_time,1,10)=dt  then 1 else 0 end is_sell_status_3 -- 停售状态
          ,0 ctob_deal_busi_code 
          ,null sku_type
     from guazi_dw_dwd.dim_ctob_auction_car_source_ymd -- B端车源信息维表
     where dt='${date_y_m_d}'
     and sell_status in (0,3) -- 车源售出状态 0: 在售,1:已定,2:已售,3:停售,-1: 上架失败

     union all 

     select 
          a.* 
     from 
     (
          select
          dt 
          ,clue_id 
          ,case when sku_status_code=10 then 1 else 0 end is_sell_status_0  -- 可售状态
          ,case when car_source_status=3  and substr(stop_sale_time,1,10)=dt then 1 else 0 end is_sell_status_3 -- 停售状态
          --,ctob_busi_type_code
          ,3 ctob_deal_busi_code 
          ,sku_type -- 商品类型
          from guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd  -- toc售卖车源明细
          where dt='${date_y_m_d}'     
     )a
    join  car_source b on a.clue_id=b.clue_id 
)
,a as 
(
     SELECT
          dt
          ,clue_id 
          ,ctob_deal_busi_code  -- 拍卖成交业务类型：1C2B（默认）,2B2B,3C2C,4收车,5回购车C2B做工,6回购车B2B做工
          ,sum(case when cb_sale_type='toc' then onshelf_num else auction_num end ) auction_num -- cb_sale_type是cb同售类型，onshelf_num上架量，auction_num上拍量
          ,sum(deliver_num) deliver_num -- 已定量
          ,0 sell_status_num
          ,0 stop_sell_num 
          ,null sku_type
     from guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd -- 线索转化截面表
     where dt between '${start}' and '${date_y_m_d}'
     and (deliver_num>0 or onshelf_num>0 or auction_num>0) -- 已定量 上架量 上拍量>0
     group by   dt
          ,clue_id 
          ,ctob_deal_busi_code

     union all 
     
     SELECT
          dt
          ,clue_id 
          ,ctob_deal_busi_code -- 拍卖成交业务类型
          ,0 auction_num -- 上拍量
          ,0 deliver_num -- 已定量
          ,count(distinct case when is_sell_status_0=1 then clue_id end) sell_status_num 
          ,count(distinct case when is_sell_status_3=1 then clue_id end)  stop_sell_num 
          ,sku_type -- 商品类型
     from car_source_sell_status -- 车源销售状态
     group by   dt
          ,clue_id 
          ,ctob_deal_busi_code
		,sku_type
),
once_reflow as (
     select
          clue_id
          ,substr(first_auction_time, 1, 10) first_auction_date -- 首次上拍时间
          ,is_once_reflow -- 是否回流过，1-是，0-否
          ,is_inspection_collect  -- 是否检测收车，1-是，0-否
        from guazi_dw_dw.dw_ctob_auction_car_source_statistic_ymd -- 车速拍车辆竞拍信息汇总表
        where dt = '${date_y_m_d}'
)


SELECT
    -- 新增列1: 上架渠道
    CASE
        WHEN CONCAT(t.ctob_busi_type_code, t.cb_sale_type) = 'C线索B收车' THEN 'B端收车量'
        WHEN CONCAT(t.ctob_busi_type_code, t.cb_sale_type) = 'C线索C收车' THEN 'C端收车量'
        WHEN CONCAT(t.ctob_busi_type_code, t.cb_sale_type) IN ('B收车toc', 'B收车tob') THEN 'B端自营'
        WHEN CONCAT(t.ctob_busi_type_code, t.cb_sale_type) IN ('C收车toc', 'C收车tob') THEN 'C端自营'
        WHEN CONCAT(t.ctob_busi_type_code, t.cb_sale_type) = 'C线索toc' THEN 'C2C'
        WHEN CONCAT(t.ctob_busi_type_code, t.cb_sale_type) = 'C线索tob' THEN 'C2B'
        ELSE '其他'
    END AS `上架渠道`,

    -- 新增列2: 组合 (拼接字段)
    CONCAT(t.ctob_busi_type_code, t.cb_sale_type) AS `组合`,
	
    -- 原有所有列 (保持原结构不变)
    t.dt
	,t.ctob_busi_type_code
	,t.cb_sale_type
	,t.fuel_type
	,t.model_price_region
	,t.model_price_region_wide
	,t.is_once_reflow
	,t.auction_num
	,t.deliver_num
	,t.sell_status_num
	,t.stop_sell_num

FROM (
    SELECT /*+ REPARTITION(1) */
        a.dt
        ,case when ctob_busi_type_code=1 then 'C线索'
              when ctob_busi_type_code=9 then 'B收车'
              when ctob_busi_type_code=10 then 'C收车' end ctob_busi_type_code
        ,case when ctob_deal_busi_code=4 then 'C收车'
              when ctob_deal_busi_code=7 then 'B收车'
              when ctob_deal_busi_code=3 then 'toc'
              else 'tob'
         end cb_sale_type
        ,fuel_type -- 燃油类型
        ,model_price_region -- 价格带
		,model_price_region_wide -- 宽价格带
        ,case when c.is_once_reflow = 1 then '回流' else '未回流' end as is_once_reflow
        ,sum(auction_num) auction_num -- 上拍量
        ,sum(deliver_num) as deliver_num -- 已定量
        ,sum(case when sku_type is null then sell_status_num
                  when ctob_busi_type_code=1 and sku_type=4 then  sell_status_num
                  when ctob_busi_type_code=10 then sell_status_num else 0 end ) sell_status_num
        ,sum(stop_sell_num) stop_sell_num

    from a
    left join car_source b on a.clue_id=b.clue_id
    left join once_reflow c on a.clue_id=c.clue_id and a.dt=c.first_auction_date
    where b.ctob_busi_type_code in (1,9,10) -- 拍卖业务类型码
    group by 1,2,3,4,5,6,7
) t