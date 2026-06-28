/*
文件: 经营-截面2-净已定量.sql
指标: 净已定量quantity_set|单均收入|总收入|总收入（脱敏版单上架100）|总收入（脱敏版C2B1000）
业务: C1车源净已定量统计及收入测算
场景: 统计C1车源按圈车类型、首上架渠道、售出渠道的净已定量（已定-退定），并关联渠道单均收入系数折算总收入
标签: 截面|圈车|净已定量|单均收入|总收入|C1|已定|退定|B2C|渠道|系数|收入测算|经营周报|财务|财分|首上架
维度: dt|圈车类型|首上架渠道|售出渠道|selling_channel|finance_selling_channel
核心表: dw_ctob_c1_tob_toc_appoint_detail_ymd|dm_e_commerce_orders_detail_ymd|dw_ctob_c1_car_source_ymd|finance_weekly_avg_order_revenue
作者: 文国庆
描述: C1车源的圈车类型、首上架渠道、售出渠道、净已定量、单均收入、总收入（财务给的数据）
*/
select 
    t1.prepay_time as dt,
	t1.`圈车类型`,
	t1.`首上架渠道`,
	t1.`售出渠道`,
	t1.selling_channel,
	t1.finance_selling_channel,
    t1.quantity_set,
    -- ★ 修改点1：如果区间精确匹配(t2)没匹配上，则使用兜底匹配(t3)
	COALESCE(t2.avg_order_revenue, t3.avg_order_revenue) as `单均收入`,
	t1.quantity_set * COALESCE(t2.avg_order_revenue, t3.avg_order_revenue) as `总收入`,
	t1.quantity_set * COALESCE(t2.avg_order_revenue, t3.avg_order_revenue)*18710000.000000 / 132682193.3278990  as `总收入（脱敏版单上架100）`,
	t1.quantity_set * COALESCE(t2.avg_order_revenue, t3.avg_order_revenue)*19614000.000000 / 70757759.434181 as `总收入（脱敏版C2B1000）`
	
from
(
    select 
        t1.prepay_time
        ,case when selling_channel in ('实体寄售','虚拟寄售','C_purchase_C_sale') then 'C售出' 
                when selling_channel in ('C2B','B_purchase_B_sale','C_purchase_B_sale') then 'B售出' 
				when selling_channel in ('B2C') then 'B2C' 
                else selling_channel 
            end as `售出渠道`
        ,case when selling_channel in ('C_purchase_C_sale') then '自营Ctoc'
                    when selling_channel in ('C_purchase_B_sale') then '自营Ctob'
                    when selling_channel in ('B_purchase_B_sale') then '自营B'
                    when selling_channel in ('实体寄售') then '实体寄售'
                    when selling_channel in ('虚拟寄售') then '虚拟寄售'
                    when selling_channel in ('C2B') then 'C2B'
					when selling_channel in ('B2C') then 'B2C' 
                else null end as selling_channel
        ,case when selling_channel in ('C_purchase_C_sale') then 'C收车2C'
                    when selling_channel in ('C_purchase_B_sale') then 'C收车2B'
                    when selling_channel in ('B_purchase_B_sale') then 'B收车2B'
                    when selling_channel in ('实体寄售') then 'C2C-实体寄售'
                    when selling_channel in ('虚拟寄售') then 'C2C-虚拟寄售'
                    when selling_channel in ('C2B') then 'C2B'
					when selling_channel in ('B2C') then 'B2C' 
                else null end as finance_selling_channel
        ,`圈车类型`
        ,`首上架渠道`
        ,IFNULL(sum(quantity_set),0)as quantity_set 
    from 
    (
         select -- C1已定
            substr(prepay_time,1,10) prepay_time
            ,clue_id
                ,case when ctob_busi_type_code in (1) and ctob_deal_busi_code not in (-1,3,8) then 'C2B'
                      when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then 'B_purchase_B_sale' 
                      when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) and is_consign_resell = 1 then '实体寄售'
                      when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) and is_consign_resell != 1 then '虚拟寄售'
                      when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then 'C_purchase_C_sale'
                      when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1,3) then 'C_purchase_B_sale'  
                    else concat(ctob_busi_type_code,'_',ctob_deal_busi_code)end as selling_channel
                ,1 as quantity_set
        from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
        where dt ='${date_y_m_d}'
          and ctob_busi_type_code in(1,9,10)
        and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
        and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
          group by 1,2,3,4
         
		union ALL
		
         select -- C1已定后退
            substr(refund_time,1,10) refund_time
            ,clue_id
                ,case when ctob_busi_type_code in (1) and ctob_deal_busi_code not in (-1,3,8) then 'C2B'
                      when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then 'B_purchase_B_sale' 
                      when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) and is_consign_resell = 1 then '实体寄售'
                      when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) and is_consign_resell != 1 then '虚拟寄售'
                      when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then 'C_purchase_C_sale'
                      when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1,3) then 'C_purchase_B_sale'  
                    else concat(ctob_busi_type_code,'_',ctob_deal_busi_code)end as selling_channel
                ,-1 as quantity_set
        from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
        where dt ='${date_y_m_d}'
          and ctob_busi_type_code in(1,9,10)
        and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
        and substr(refund_time,1,10) between '${start}' AND '${date_y_m_d}'
          group by 1,2,3,4	
		
		union ALL
		
		SELECT -- B2C已定
			substr(deliver_car_prepay_time,1,10) AS prepay_time
			,clue_id
			,'B2C' as selling_channel
			, 1 as quantity_set
		from guazi_dw_dm.dm_e_commerce_orders_detail_ymd
		where dt='${date_y_m_d}' 
		and substr(deliver_car_prepay_time,1,10) BETWEEN '${start}' AND '${date_y_m_d}'
		and busi_type=1 -- B2C
		GROUP BY 1,2,3,4

		union ALL
		
		SELECT -- B2C已定后退
			substr(refund_time,1,10) AS refund_time
			,clue_id
			,'B2C' as selling_channel
			, -1 as quantity_set
		from guazi_dw_dm.dm_e_commerce_orders_detail_ymd
		where dt='${date_y_m_d}' 
		and substr(refund_time,1,10) BETWEEN '${start}' AND '${date_y_m_d}'
		and busi_type=1 -- B2C
		GROUP BY 1,2,3,4
    )t1
    left join 
    (
        SELECT distinct 
            substr(onshelf_time, 1, 10) AS dt,
            CASE WHEN car_collect_platform in (2,3) OR consign_choose_type IN (1, 2) THEN 'C圈车' ELSE 'B圈车' END AS `圈车类型`,
            CASE
                WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
                WHEN first_onshelf_biz_line =  'C2C独售-门店' THEN'首上实体寄售'
                WHEN first_onshelf_biz_line =  'C2B' THEN '首上C2B'
                WHEN first_onshelf_biz_line =  '自营C' THEN '首上自营C'
                WHEN first_onshelf_biz_line =  '自营B' THEN '首上自营B'
                ELSE first_onshelf_biz_line
            END AS `首上架渠道`,
            COALESCE(t1.clue_id_self,t1.clue_id) clue_id
        FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
            WHERE t1.dt = '${date_y_m_d}'
          AND t1.is_c1_clue = 1 -- C1车源
          and substr(onshelf_time,1,10) is not null -- 已经上架 
    )t2 on t1.clue_id = t2.clue_id and t1.selling_channel != 'B2C'
    group by 1,2,3,4,5,6
) t1 

-- ★ 修改点2：保留之前的精确匹配逻辑
left join guazi_dw_import.finance_weekly_avg_order_revenue t2 
    on t1.finance_selling_channel = t2.biz_type
    and t1.prepay_time >= t2.start_date 
    and t1.prepay_time <= t2.end_date

-- ★ 修改点3：增加兜底匹配逻辑，通过 ROW_NUMBER 取每个 biz_type 时间最近(end_date倒排第一)的数据
left join (
    select biz_type, avg_order_revenue
    from (
        select 
            biz_type, 
            avg_order_revenue,
            row_number() over(partition by biz_type order by end_date desc) as rn
        from guazi_dw_import.finance_weekly_avg_order_revenue
    ) tmp 
    where rn = 1
) t3 on t1.finance_selling_channel = t3.biz_type;