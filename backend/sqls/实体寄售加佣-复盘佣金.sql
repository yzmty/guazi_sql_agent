/*
文件: 实体寄售加佣-复盘佣金.sql
指标: quantity_set（净已定量）|service_fee（应收佣金）|actual_service_fee（实收佣金）|purchase_income（价差收入）|总收入|deal_price（B端客单价）|deal_price_1（C端客单价）|seller_model_price（模型价）|commission（意向金佣金）
业务: 实体寄售加佣金实验的Cohort分析数据源
场景: 主要用于复盘C2C实体寄售的佣金，和用户服务中心商业分析部的佣金对齐（佣金/已定量和用户服务中心商业分析部对齐）
标签: 实体寄售|佣金|cohort|已定量|收入|客单价|C1|C2C|实验
维度: prepay_time（已定日期）|首上架渠道|selling_channel（售出渠道）|渠道（C端自营/B端自营）|is_consign_resel（是否实体寄售）|fuel_type（能源类型）
核心表: dw_ctob_c1_tob_toc_appoint_detail_ymd|dw_ctob_c1_car_source_ymd|dm_e_commerce_orders_detail_ymd|dim_ctob_auction_car_source_ymd|dwd_com_sale_orders_ymd|dwb_order_center_order_expense_day
作者: 文国庆|杨悦芳
描述: 实体寄售加佣金实验数据源，按渠道和首上架渠道汇总已定量、收入、客单价、佣金
*/
with orders_bc_intent AS (
 select * from
 (SELECT
 substr(intention_money_finish_time, 1, 10) dt,
 clue_id,order_id,cancel_time,
 row_number () over (partition by substr(intention_money_finish_time, 1, 10),clue_id order by intention_money_finish_time desc ) rn
 FROM
 guazi_dw_dwd.dwd_com_sale_orders_ymd
 WHERE dt = '${date_y_m_d}' 
 AND substr(intention_money_finish_time, 1, 10) BETWEEN '${start_time}' AND '${date_y_m_d}'
  ) tt where rn=1
 )

, commission as ( -- C2C的佣金
   SELECT
      order_id,
        (sum(IF(expense_id IN ('10169', '200153', '200152', '200154'), amount, null)) / 100) commission
        FROM guazi_dw_dwb.dwb_order_center_order_expense_day 
    WHERE dt = '${date_y_m_d}' 
        AND expense_id IN ('10169', '200153', '200152', '200154')
        AND enabled = 1
        GROUP BY 1
        )
	
,orders_info as ( 
  select 
  a.dt,a.order_id,a.clue_id,a.cancel_time,b.commission
  from orders_bc_intent a 
  left join commission b on a.order_id =b.order_id
  
)

select 
    case 
            when selling_channel in ('C_purchase_C_sale','C_purchase_B_sale') then 'C端自营' 
            when selling_channel = 'B_purchase_B_sale' then 'B端自营' 
            else selling_channel 
        end as `渠道`,
    prepay_time as dt,
	`首上架渠道`,
    selling_channel,
	is_consign_resel,
    quantity_set,
    service_fee, -- 应收佣金
    actual_service_fee, -- 实收佣金
    purchase_income, -- 价差收入
    `总收入` ,
	deal_price ,
	deal_price_1 , -- toC用这个！ 
	seller_model_price ,
	commission
from
(select 
    t1.prepay_time
	,t2.fuel_type  -- 燃油类型
	
	
    ,t1.selling_channel
   
    ,case when t1.selling_channel = 'C2C' then t1.is_consign_resel else '全部' end as is_consign_resel
    ,case when t2.first_onshelf_biz_line in ('C2C独售-虚拟' ,'C2C独售-门店') then 'C2C' else t2.first_onshelf_biz_line end as  `首上架渠道`
    ,IFNULL(sum(t1.quantity_set),0)as quantity_set
	,IFNULL(sum(t1.prepay_before_discount_sales_service_fee),0) as service_fee
	,IFNULL(sum(t1.prepay_sales_service_fee),0) as actual_service_fee
	,IFNULL(sum(t1.acquisition_spread_income),0) as purchase_income
	,IFNULL(sum(case when t1.selling_channel = 'C2C' then t1.prepay_before_discount_sales_service_fee else t1.prepay_sales_service_fee end),0)
    + IFNULL(sum(t1.acquisition_spread_income),0) as `总收入`
	,sum(t3.deal_price)deal_price -- 这个可以用来看toB的客单价，但是不能用来看toC的客单价。
	
   ,sum(t1.deal_price_1)deal_price_1 -- 这个就是toC的客单价
   ,sum(c2b.seller_model_price)seller_model_price
   ,sum(commission) commission
from 
(
	 select -- 已定
        substr(prepay_time,1,10) prepay_time
        ,clue_id
		,c_order_id
			,case when ctob_busi_type_code in (1) and ctob_deal_busi_code not in (-1,3,8) then 'C2B'
          when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then 'B_purchase_B_sale' 
          when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) then 'C2C' 
          when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then 'C_purchase_C_sale'
          when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1,3) then 'C_purchase_B_sale'  
		    else concat(ctob_busi_type_code,'_',ctob_deal_busi_code)end as selling_channel ,
		
	case when is_consign_resell=1 then '实体' else '非实体' end as is_consign_resel
			,1 as quantity_set
			,sum(deal_price) deal_price_1
			,sum(prepay_before_discount_sales_service_fee) prepay_before_discount_sales_service_fee
			,sum(prepay_sales_service_fee) prepay_sales_service_fee
			,sum(acquisition_spread_income) acquisition_spread_income
    from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
    where dt ='${date_y_m_d}'
	  and ctob_busi_type_code in(1,9,10)
    and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
    and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
	  group by 1,2,3,4,5
	
	
)t1
left join 
(
    select 
          substr(onshelf_time,1,10) dt
          ,first_onshelf_biz_line
		  ,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type 
          ,case when clue_id_self is not null then clue_id_self else clue_id end as clue_id
     from guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
     where dt ='${date_y_m_d}'
     and is_c1_clue = 1 -- C1车源
     and substr(onshelf_time,1,10) is not null -- 已经上架
     group by 1,2,3 ,4
)t2 on t1.clue_id = t2.clue_id
left join 
(
SELECT 
	order_id
	, sum(deal_price) deal_price
from guazi_dw_dm.dm_e_commerce_orders_detail_ymd
where dt='${date_y_m_d}' 
and substr(deliver_car_prepay_time,1,10) is not null
GROUP BY 1
) t3 
on t1.c_order_id=t3.order_id
left join 
(
select
	clue_id,
	sum(seller_model_price)seller_model_price
from guazi_dw_dwd.dim_ctob_auction_car_source_ymd
where dt = '${date_y_m_d}'
  and ctob_busi_type_code in (0,1,2)
  and seller_model_price is not null
  and onshelf_time is not null
 group by 1
) c2b on t1.clue_id = c2b.clue_id
left join 
(
select 
order_id ,
sum(commission) commission
from orders_info 
group by 1
)
o on o.order_id=t1.c_order_id -- 必须用order_id关联！
group by 1,2,3,4,5
 ) t