/*
文件: 首上架数据源2-已定首次上架数据.sql
指标: 已定量|应收服务费|实收服务费|价差收入|总收入
业务: C1首上架渠道已定量及收入汇总
场景: 按已定日期、已定渠道、首上架渠道汇总C1车源的已定量及各类收入，用于分析不同首上架渠道的收入贡献
标签: 首上架|已定量|价差|收入|C1
维度: 已定时间|已定渠道最终|已定渠道|首上架渠道
核心表: dw_ctob_c1_tob_toc_appoint_detail_ymd|dw_ctob_c1_car_source_ymd
作者: 未知|杨悦芳
描述: 按首上架渠道汇总已定量、应收/实收服务费、价差收入、总收入
*/
with a as (
select 
    t1.prepay_time as prepay_time 
    ,case when ctob_busi_type_code in (1) and ctob_deal_busi_code not in (-1,3,8) then 'C2B'
          when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then 'B收车B端售卖' 
          when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) then 'C2C-C端售卖' 
          when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then 'C收车-C端售卖'
          when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1,3) then 'C收车-B端售卖'  
		    else concat(ctob_busi_type_code,'_',ctob_deal_busi_code)end as channel 
    ,case when first_onshelf_biz_line in ('C2C独售-虚拟','C2C独售-门店') then 'C2C' else first_onshelf_biz_line end as first_channel  

    ,count(distinct t1.clue_id)as appoint_cnt 
	  ,IFNULL(sum(prepay_before_discount_sales_service_fee),0) as receivable_fee 
	  ,IFNULL(sum(prepay_sales_service_fee),0) as actual_fee  
	  ,IFNULL(sum(acquisition_spread_income),0) as spread_income  
	  ,IFNULL(sum(case when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) then prepay_before_discount_sales_service_fee else prepay_sales_service_fee end),0)+IFNULL(sum(acquisition_spread_income),0) as total_income  
   
from 
(
	 select 
        substr(prepay_time,1,10) prepay_time
        ,clue_id
		    ,ctob_busi_type_code
		    ,ctob_deal_busi_code
		    ,sum(prepay_before_discount_sales_service_fee) prepay_before_discount_sales_service_fee
		    ,sum(prepay_sales_service_fee) prepay_sales_service_fee
		    ,sum(acquisition_spread_income) acquisition_spread_income
    from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
    where dt ='${date_y_m_d}'
	  and ctob_busi_type_code in(1,9,10)
    and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
    and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
	  group by 1,2,3,4
	
)t1
left join 
(
    select 
          substr(onshelf_time,1,10) dt
          ,first_onshelf_biz_line
          ,case when clue_id_self is not null then clue_id_self else clue_id end as clue_id
     from guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
     where dt ='${date_y_m_d}'
     and is_c1_clue = 1 -- C1车源
     and substr(onshelf_time,1,10) is not null -- 已经上架
     group by 1,2,3 
)t2 on t1.clue_id = t2.clue_id
group by 1,2,3
)

select 
    
    prepay_time as `已定时间`,
	case channel
        when 'C2B' then 'C2B'
        when 'C2C-C端售卖' then 'C2C'
        when 'C收车-B端售卖' then '自营C'
        when 'C收车-C端售卖' then '自营C'
        when 'B收车B端售卖' then '自营B'
        else channel
    end as `已定渠道最终`,
    channel as `已定渠道`,
    first_channel as `首上架渠道`,
    appoint_cnt as `已定量`,
    receivable_fee as `应收服务费`,
    actual_fee as `实收服务费`,
    spread_income as `价差收入`,
    total_income as `总收入`
from a