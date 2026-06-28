/*
文件: 价格数据源2-暗拍成交出价深度.sql
指标: 暗拍车商实付价|车主到手价|模型价|暗拍成交出价深度
业务: C1的C2B拍场
场景: 分析C2B拍场的暗拍成交出价深度
标签：暗拍|成交|出价深度|到手价|模型价
维度: dt|燃油类型fuel_type|模型价model_price_region
核心表: dwd_ctob_auction_bid_ymd|dw_ctob_appoint_prepay_detail_ymd|dw_ctob_appoint_prepay_detail_ymd_2
作者: 文国庆|杨悦芳
描述: 分析C2B拍场的暗拍成交出价深度|暗拍成交出价深度 = 暗拍车商实付价 / 车主到手价模型价
*/
-- 暗拍成交出价深度 = 暗拍车商实付价 / 车主到手价模型价
with a as (
select
		-- substr(a.auction_end_time,1,10) as dt -- 开标时间(场次结束)
		case
        when (model_price * 1.0 / 10000) > 0   and (model_price * 1.0 / 10000) <= 3   then '(0-3]'
        when (model_price * 1.0 / 10000) > 3   and (model_price * 1.0 / 10000) <= 5   then '(3-5]'
        when (model_price * 1.0 / 10000) > 5   and (model_price * 1.0 / 10000) <= 8   then '(5-8]'
        when (model_price * 1.0 / 10000) > 8   and (model_price * 1.0 / 10000) <= 12 then '(8-12]'
        when (model_price * 1.0 / 10000) > 12  then '(12+)'
		end as model_price_region -- 价格段
        ,a.bid_id
        ,a.deal_user_id
        ,a.clue_id
        ,a.bid_amount -- 出价
        ,a.bid_create_time
        ,a.auction_type -- 竞拍状态 102暗拍  103秒杀 110B2B明拍
        ,a.bid_seller_price -- 心理底价
        ,a.model_price -- 车主到手价模型价
       -- ,row_number() over(partition by clue_id,substr(auction_end_time,1,10) order by bid_amount desc ) rn 
    from  guazi_dw_dwd.dwd_ctob_auction_bid_ymd a -- 车速拍出价记录表
    where a.dt='${date_y_m_d}'
    -- and substr(a.auction_end_time,1,10) between '${start_time}' and '${date_y_m_d}'   
    and a.auction_type in(102)  -- 暗拍
  --  and a.ctob_busi_type_code in (0,1,2) -- 拍卖业务类型： 0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9:C2B收车 10:B2C收车 11:出海收车
)
,b as (
select 
		prepay_time
		,substring(b.prepay_time, 1, 10) as dt 
		,b.bid_id
		,b.clue_id
		,b.deal_price -- 已定价格
	from guazi_dw_dw.dw_ctob_appoint_prepay_detail_ymd b -- 拍卖带看到已定结点明细数据
	where b.dt='${date_y_m_d}'
	and substring(prepay_time, 1, 10) between '${start_time}' and '${date_y_m_d}'  

)
,c as (
select 
	clue_id
	,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type 
	from guazi_dw_dwd.dim_ctob_auction_car_source_ymd -- B端车源信息维表
	where
    dt = '${date_y_m_d}'
 --   and ctob_busi_type_code in (？) -- 拍卖业务类型：0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9 B收车 10C收车
)
select 
	b.dt
    ,c.fuel_type
    ,case 
    when a.model_price_region is not null and a.model_price_region <> '' 
    then a.model_price_region 
    else 'null' end model_price_region
    ,sum(b.deal_price) as deal_price_sum -- 暗拍车商实付价
    ,sum(a.model_price) as model_price_sum -- 车主到手价模型价
    ,sum(b.deal_price) / coalesce(sum(a.model_price), 0) as bid_depth_102
from b -- b当主表
left join a
    on b.bid_id = a.bid_id
  -- and a.rn = 1
left join c
    on b.clue_id = c.clue_id
where a.model_price_region is not null
group by 1, 2, 3
