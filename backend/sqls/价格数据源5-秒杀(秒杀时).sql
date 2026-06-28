/*
文件: 价格数据源5-秒杀时出价深度.sql
指标: 秒杀车商出价|车主心理底价|秒杀时出价深度
业务: C1的C2B秒杀场
场景: 分析C2B秒杀场的秒杀当时出价深度
标签：秒杀|当时|出价深度|心理底价|模型价
维度: dt|燃油类型fuel_type|模型价model_price_region
核心表: dwd_ctob_auction_bid_ymd|dw_ctob_appoint_prepay_detail_ymd|dw_ctob_appoint_prepay_detail_ymd_2
作者: 文国庆|杨悦芳
描述: 分析C2B秒杀场的秒杀当时出价深度|秒杀当时出价深度 = 秒杀车商出价 / 车主心理底价
*/
-- 秒杀当时出价深度 = 秒杀车商出价/ 车主心理底价（秒杀定价出价时）
with a as (
select
		substr(a.auction_end_time,1,10) as dt -- 出价时间
		,case
        when (bid_seller_price * 1.0 / 10000) > 0   and (bid_seller_price * 1.0 / 10000) <= 3   then '(0-3]'
        when (bid_seller_price * 1.0 / 10000) > 3   and (bid_seller_price * 1.0 / 10000) <= 5   then '(3-5]'
        when (bid_seller_price * 1.0 / 10000) > 5   and (bid_seller_price * 1.0 / 10000) <= 8   then '(5-8]'
        when (bid_seller_price * 1.0 / 10000) > 8   and (bid_seller_price * 1.0 / 10000) <= 12 then '(8-12]'
        when (bid_seller_price * 1.0 / 10000) > 12  then '(12+)'
		end as model_bid_seller_price -- 价格段
        ,a.bid_id
        ,a.deal_user_id
        ,a.clue_id
        ,a.bid_amount -- 出价
        ,a.auction_end_time
        ,a.auction_type -- 竞拍状态 102暗拍  103秒杀 110B2B明拍
        ,a.bid_seller_price -- 心理底价
        ,a.model_price -- 车主到手价模型价
        ,row_number() over(partition by clue_id,substr(auction_end_time,1,10) order by bid_amount desc ) rn 
    from  guazi_dw_dwd.dwd_ctob_auction_bid_ymd a -- 车速拍出价记录表
    where a.dt='${date_y_m_d}'
    and substr(a.auction_end_time,1,10) between '${start_time}' and '${date_y_m_d}'   
    and a.auction_type in(103)  -- 秒杀
 -- and a.ctob_busi_type_code in (0,1,2) -- 拍卖业务类型： 0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9:C2B收车 10:B2C收车 11:出海收车
)
-- ,b as (
-- select 
-- prepay_time
-- ,substring(b.prepay_time, 1, 10) as dt 
-- ,b.bid_id
-- ,b.clue_id
-- ,b.deal_price -- 已定价格
-- from guazi_dw_dw.dw_ctob_appoint_prepay_detail_ymd b -- 拍卖带看到已定结点明细数据
-- where b.dt='${date_y_m_d}'
-- and substring(prepay_time, 1, 10) between '${start_time}' and '${date_y_m_d}'  

-- )
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
	 a.dt
    ,c.fuel_type
    ,case 
    when a.model_bid_seller_price is not null and a.model_bid_seller_price <> '' 
    then a.model_bid_seller_price 
    else 'null' end model_bid_seller_price
    ,sum(a.bid_amount) as bid_amount -- 秒杀车商出价
    ,sum(a.bid_seller_price) as bid_seller_price -- 车主心理底价
    ,sum(a.bid_amount) / coalesce(sum(a.bid_seller_price), 0) as bid_depth_103
	-- 分母大了，原因是bid_seller_price车主心理底价对应的车子多了，成交是只有成交的车才算进去
from a
left join c
on a.clue_id = c.clue_id
where rn=1 and a.model_bid_seller_price is not null 
group by 1, 2, 3