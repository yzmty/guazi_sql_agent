/*
file:供给ch4-线索_上架.sql,
指标:线索量|T0上架量|T1上架量|T3上架量|T7上架量|T14上架量|T21上架量|T30上架量 
业务：C1
场景：漏斗表|供给周报的cohort|包括瓜子线索-上架量
标签：供给|线索量|人数|漏斗|转率|cohort|瓜子新客|瓜子新客数量|T0上架量|T1上架量|T3上架量|T7上架量|T14上架量|T21上架量|T30上架量
维度：日期dt|投放类型toufang_type|渠道channel_level|渠道类型名称channel_type_name|渠道名称channel_name_ctob
核心表：dm_ctob_clue_detail_transform_csd_inc_ymd|dwd_ctob_top_channel_all_info_ymd
作者：宋明瑞|杨悦芳
描述：用于供给周报的瓜子线索-上架量的漏斗转化率
*/
-- 4..线索-上架
--------------------------------------
with 
clue as (
-- 线索
    select 
	clue_id,
        dt as dt, 
        is_salvage,
        is_75_city,
        cb_sale_type,
        clue_num,
        evaluate_num,
        onshelf_num,
        deliver_num,
        refund_num,
        attribution_type,
        ca_s,
        ca_n,
        ctob_busi_type_code
    FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd    
    WHERE dt BETWEEN '${start}' AND '${date_y_m_d}' 
    and ctob_busi_type_code IN (0,1)
	and clue_num >0
	and is_salvage = 0 and is_75_city = '是'
	
),

onshelf as (
-- 上架
 select 
 clue_id,dt
    FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd    
    WHERE dt BETWEEN '${start}' AND '${date_y_m_d}' 
    and ctob_busi_type_code IN (0,1)
	and onshelf_num >0
	and cb_sale_type='tob'
	
)
,
channel as 
(
    select 
          ca_s
         ,ca_n
         ,case when channel_label_ch_name like '%非投放%' then '非投放'
               when line_id  in ('2','3')  then  '投放'
            else coalesce(toufang_type,'非投放') end  toufang_type
         ,channel_type_name_ctob  channel_type_name
         ,customer_type_ch_name customer_type_name
         ,phone_system_ch_name  phone_system
         ,new_channel_ch_name new_channel
         ,customer_type
         ,agent_ch_name agent
         ,channel_name_ctob
         ,channel_tag_id
         ,channel_tag
         ,line_id
         ,channel_level1
         ,channel_level2
    from guazi_dw_dwd.dwd_ctob_top_channel_all_info_ymd
    where dt='${date_y_m_d}'  
)

select 
dt
,toufang_type
,case when channel_level2 = '非主端' then '非主端-端产品'
when channel_level2 = '直投' then '表单'
when channel_level1 = '商务拓展' then '商务'
when channel_level1 = '端产品' then '主端'
else channel_level1 end as channel_level,
case when channel_type_name_wide is null then '无归因' else channel_type_name_wide end channel_type_name,
case when channel_name is null then '无归因' else channel_name end channel_name_ctob,

count(distinct clue_id) as clue_num,

count(distinct case when datediff(onshelf_dt, dt) = 0    then clue_id else null end) as onshelf_t0, -- 上架
count(distinct case when datediff(onshelf_dt, dt) <=1    then clue_id else null end) as onshelf_t1, 
count(distinct case when datediff(onshelf_dt, dt) <=3    then clue_id else null end) as onshelf_t3, 
count(distinct case when datediff(onshelf_dt, dt) <=7    then clue_id else null end) as onshelf_t7, 
count(distinct case when datediff(onshelf_dt, dt) <=14   then clue_id else null end) as onshelf_t14, 
count(distinct case when datediff(onshelf_dt, dt) <=21   then clue_id else null end) as onshelf_t21, 
count(distinct case when datediff(onshelf_dt, dt) <=30   then clue_id else null end) as onshelf_t30 

from 
(
    select a.dt,c.dt as onshelf_dt,a.clue_id,
    
    case when a.attribution_type=1 then '投放' when a.attribution_type=2 then '非投放' else coalesce(b.toufang_type,'非投放') end as toufang_type,
    case when a.ca_s = 'sop_zijianxiansuo' then '网销自建' when a.ctob_busi_type_code in ('3','7') then 'B2B' else coalesce(b.channel_type_name,'瓜子二手车') end as channel_type_name_wide,
    case when a.ca_s = 'sop_zijianxiansuo' then '网销自建' else b.channel_name_ctob end as channel_name,
    case when a.ca_s = 'sop_zijianxiansuo'  THEN '端产品' 
               when a.ctob_busi_type_code  in ('3','7')  then 'B2B'
               else coalesce(channel_level1,'端产品') end as channel_level1,
    case when a.ca_s = 'sop_zijianxiansuo'  then '主端' 
               when a.ctob_busi_type_code in ('3','7') then 'B2B'
               else coalesce(channel_level2,'主端') end channel_level2,
    b.channel_type_name,
    b.channel_name_ctob,
    b.customer_type_name
    from clue a -- 线索
	left join onshelf c on a.clue_id = c.clue_id -- 上架
    left join channel b on a.ca_s = b.ca_s and a.ca_n = b.ca_n 
) t
group by 1,2,3,4,5