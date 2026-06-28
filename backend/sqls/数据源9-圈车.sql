/*
文件: 数据源9-圈车.sql
指标: 提交检测报告量|圈车量|上架量|出海圈车量|C自营圈车量|C自营圈车有效报价量|C自营圈车收车成功量|B自营圈车量|B自营圈车有效报价量|B自营圈车收车成功量|C2C圈车量|C2C有效报价量|C2C圈车-提交寄售成功量|C2C圈车量-虚拟|C2C有效报价量-虚拟|C2C圈车量-提交寄售成功量-虚拟|C2C圈车量-虚拟&实体|C2C有效报价量-虚拟&实体|C2C圈车量-虚拟&实体
业务: C1圈车后的全链路分析
场景: 按报告日期、城市、是否实体寄售统计C1车源从提交检测报告到圈车、上架的全链路转化，区分出海/C自营/B自营/C2C等圈车类型，并细分虚拟/实体寄售模式
标签: 圈车|检测报告|上架|出海|C自营|B自营|C2C|虚拟寄售|实体寄售|有效报价|收车成功|C1
维度: 是否实体寄售|report_dt（报告日期）|city_name（城市）
核心表: dw_ctob_evaluate_task_ymd|dim_ctob_auction_car_source_ymd
作者: 孙丹
描述: 按报告日期、城市统计C1车源圈车转化全链路
*/
--- 圈车部分SQL           
select 
	case when city_name in (
		'保定','北京','成都','大连','东莞','佛山','福州','广州','贵阳','哈尔滨',
		'邯郸','合肥','呼和浩特','惠州','济南','济宁','金华','昆明','兰州','廊坊',
		'临沂','洛阳','南昌','南宁','青岛','泉州','厦门','深圳','沈阳','石家庄',
		'苏州','太原','唐山','天津','潍坊','温州','武汉','西安','徐州','烟台',
		'长春','长沙','郑州','中山','重庆','珠海'
	) then '是' else '否' end as `是否实体寄售`
	,t1.report_dt
	-- ,t1.label
	,city_name
	-- 整体
	,count(distinct t1.clue_id) as `提交检测报告量`
	,count( distinct case when  (car_collect_status = 1 and car_collect_platform in (1,2,3)) or is_submit_consign_success is not null then t1.clue_id else null end) as `圈车量`
	,count(distinct case when t3.dt is not null then t1.clue_id else null end) as `上架量`
	-- 出海
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 3 then t1.clue_id end ) as `出海圈车量`
	-- C自营
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 2 then t1.clue_id end ) as `C自营圈车量`
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 2 and car_collect_base_price>0 and car_collect_confirm_model_price >0 and car_collect_xingjiabi <=1.1 then t1.clue_id end )as `C自营圈车有效报价量`
	-- 收车车主心理底价>0,收车车主确认模型报价>0,收车车主心理底价/收车车主确认模型报价<1.1
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 2 and car_collect_result =1 then t1.clue_id end ) as `C自营圈车收车成功量`
	-- B自营
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 1 then t1.clue_id end ) as `B自营圈车量`
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 1 and car_collect_base_price>0 and car_collect_confirm_model_price >0 and car_collect_xingjiabi <=1.1 then t1.clue_id end )as `B自营圈车有效报价量`
	,count(distinct case when car_collect_status = 1 and car_collect_platform = 1 and car_collect_result =1 then t1.clue_id end ) as `B自营圈车收车成功量`

	-- C2C
	,count(distinct case when C_label = 'C中' then t1.clue_id end ) as `C2C圈车量`
	,count(distinct case when C_label = 'C中' and car_owner_choose_price >0 and consign_sale_price>0 and car_owner_xingjiabi <=1.1 then t1.clue_id end ) as `C2C有效报价量`
	,count(distinct case when C_label = 'C中' and is_submit_consign_success = 1 then t1.clue_id end ) as `C2C圈车-提交寄售成功量`
	
	,count(distinct case when C_label = 'C中' then t1.clue_id end ) as `C2C圈车量`

	-- C2C-虚拟
	,count(distinct case when C_label = 'C中' and consign_choose_type = 1  then t1.clue_id end ) as `C2C圈车量-虚拟`
	,count(distinct case when C_label = 'C中' and consign_choose_type = 1  and car_owner_choose_price >0 and consign_sale_price>0 and car_owner_xingjiabi <=1.1 then t1.clue_id end ) as `C2C有效报价量-虚拟`
	,count(distinct case when C_label = 'C中' and consign_choose_type = 1  and is_submit_consign_success = 1 then t1.clue_id end ) as `C2C圈车量-提交寄售成功量-虚拟`

	-- C2C-虚拟&实体
	,count(distinct case when C_label = 'C中' and consign_choose_type = 2  then t1.clue_id end ) as `C2C圈车量-虚拟&实体`
	,count(distinct case when C_label = 'C中' and consign_choose_type = 2  and car_owner_choose_price >0 and consign_sale_price>0 and car_owner_xingjiabi <=1.1 then t1.clue_id end ) as `C2C有效报价量-虚拟&实体`
	,count(distinct case when C_label = 'C中' and consign_choose_type = 2  and is_submit_consign_success = 1 then t1.clue_id end ) as `C2C圈车量-虚拟&实体`

from 
(
	select 
		substr(evaluate_submit_report_time, 1, 10) as report_dt 
		,case when car_collect_status = 1 and car_collect_platform = 3 then '出海'
			when car_collect_status = 1 and car_collect_platform = 2 then 'C自营'
			  when car_collect_status = 1 and car_collect_platform = 1 then 'B自营' else '其他' end label
	   ,clue_id
	   ,city_name
	   ,car_collect_status
	   ,car_collect_platform
	   ,consign_choose_type --寄售圈中类型 1 虚拟 2 虚拟+实体
	   ,case when first_consign_submit_time is not null then 'C中' else 'C未中' end C_label
	   ,car_collect_base_price -- 收车车主心里底价
	   ,car_collect_confirm_model_price -- 收车车主确认模型报价 元
	   ,car_collect_base_price/car_collect_confirm_model_price  car_collect_xingjiabi
	   ,car_collect_result -- 收车结果0:失败, 1:成功
	   ,car_owner_choose_price --寄售车主心里底价
	   ,consign_sale_price -- 寄售推荐寄售价/模型价
	   ,car_owner_choose_price/consign_sale_price car_owner_xingjiabi
	   ,is_submit_consign_success -- 是否提交寄售成功 1是 0否 -1默认值无意义
	from guazi_dw_dw.dw_ctob_evaluate_task_ymd
	where dt = '${date_y_m_d}'
	and ctob_busi_type= '一口价'
	and substr(evaluate_submit_report_time, 1, 10) between '${start}' AND '${date_y_m_d}'
)t1
left join 
(
	SELECT
		SUBSTRING(onshelf_time, 1, 10) AS dt
		,clue_id
	FROM guazi_dw_dwd.dim_ctob_auction_car_source_ymd
	WHERE dt = '${date_y_m_d}'
	AND SUBSTRING(onshelf_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
	AND ctob_busi_type_code IN (0,1) -- 所有C1新上架量
	group by 1,2
)t3 on t1.clue_id = t3.clue_id and t1.report_dt = t3.dt
group by 1,2,3