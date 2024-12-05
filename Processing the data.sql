/*Transfer canceled_date column with value '1899-12-30' to '2023-09-30'
--UPDATE [Subscription Cohort Analysis]
--SET canceled_date = '2023-09-30'
--WHERE canceled_date = '1899-12-30'?*/


--This is CTE has all paid customers
WITH CTE1 AS
(
SELECT * 
FROM [DataFile].[dbo].[Subscription Cohort Analysis]
WHERE was_subscription_paid = 'Yes'
)
,


/* DEAL WITH DUPLICATE CUSTOMER*/

--This CTE has all duplicate customers
CTE2 AS (
SELECT customer_id
FROM CTE1
GROUP BY customer_id
HAVING COUNT (customer_id) > 1 --Filter all duplicate customers 
--ORDER BY customer_id
)
,

--This CTE has all duplicate customers with their appearance
CTE3 AS 
(
SELECT *,
count(customer_id) over (partition by customer_id order by created_date, canceled_date) as occurences
FROM CTE1
WHERE customer_id IN (SELECT customer_id FROM CTE2)
--ORDER BY customer_id
)
,

--This CTE has duplicate customer_id appearing 1st time 
CTE4 AS 
(
SELECT *--, 'NONE' AS CUSTOMER_COHORT
FROM CTE3
WHERE occurences = 1
)
,

--This CTE has duplicate customer_id appearing 2nd time 
CTE5 AS 
(
SELECT *
FROM CTE3
WHERE occurences = 2
)
,

--This CTE has duplicate customer_id appearing 3rd time 
CTE6 AS 
(
SELECT *
FROM CTE3
WHERE occurences = 3
)
,

--This CTE was compiled by 3 tables CT4, CT5, CT6
CTE7 AS
(
SELECT CTE4.customer_id, CTE4.created_date as created_date_1, CTE4.canceled_date as canceled_date_1,
	   CTE5.created_date as created_date_2, CTE5.canceled_date as canceled_date_2,
	   CTE6.created_date as created_date_3, CTE6.canceled_date as canceled_date_3
FROM CTE4
LEFT JOIN CTE5
ON CTE4.customer_id = CTE5.customer_id
LEFT JOIN CTE6
ON CTE4.customer_id = CTE6.customer_id
)
,

--This table shows the number of days between second-time customers and first-time customers, 
--as well as between third-time customers and second-time customers, depending on CTE7.
CTE8 AS
(
SELECT *,
		DATEDIFF (MONTH, created_date_1, canceled_date_1) 
		+ 
		CASE 
			WHEN created_date_1 = canceled_date_1 then 1
			WHEN DAY(created_date_1) < DAY(canceled_date_1) then 1 
			ELSE 0
		END
		as month_span_from_created_date_1_to_canceled_date_1,

		DATEDIFF (MONTH, created_date_1, created_date_2)
		+ 
		CASE 
			WHEN created_date_1 = created_date_2 then 1
			WHEN DAY(created_date_1) < DAY(created_date_2) then 1 
			ELSE 0
		END
		as month_span_from_created_date_1_to_created_date_2,

		DATEDIFF (MONTH, created_date_2, canceled_date_2) 
		+ 
		CASE 
			WHEN created_date_2 = canceled_date_2 then 1
			WHEN DAY(created_date_2) < DAY(canceled_date_2) then 1 
			ELSE 0
		END
		as month_span_from_created_date_2_to_canceled_date_2,

		DATEDIFF (MONTH, created_date_2, created_date_3)
		+ 
		CASE 
			WHEN created_date_2 = created_date_3 then 1
			WHEN DAY(created_date_2) < DAY(created_date_3) then 1 
			ELSE 0
		END
		as month_span_from_created_date_2_to_created_date_3

FROM CTE7
)
,

--The CTE shows the interruptions between the first, second, and third subscriptions to classify cohort customers.
CTE9 AS
(
SELECT *,
month_span_from_created_date_1_to_created_date_2 - month_span_from_created_date_1_to_canceled_date_1 AS interruption_period_1,
month_span_from_created_date_2_to_created_date_3 - month_span_from_created_date_2_to_canceled_date_2 AS interruption_period_2
FROM CTE8

--WHERE interruption_MONTH_2_vs_1 <= 1
--WHERE from_created_date_1_to_created_date_3 = 0
--WHERE month_span_from_created_date_2_to_created_date_3 <> 0
)
,

--This CTE has retention customers depending on the amount of month between canceled_date_1 and created_date_2
--If the interruption_period_1 column has value = [0, 1], this is the retention customer.

CTE10 AS
(
SELECT customer_id, created_date_1 AS created_date, canceled_date_2 as canceled_date, 'RETENTION' AS CUSTOMER_COHORT
--SELECT *
FROM CTE9
WHERE interruption_period_1 IN (0,1)
	  AND
	  interruption_period_2 IS NULL
)
,

--This CTE compiles customer IDs with one-time re-subscriptions into a single row.
CTE11 AS
(
SELECT customer_id, created_date_2 as created_date, canceled_date_3 as canceled_date, 'RETENTION' AS CUSTOMER_COHORT
--SELECT *
FROM CTE9
WHERE interruption_period_1 NOT In (0,1)
	  AND
	  interruption_period_2 IN (0,1)
)
,

--This CTE has win-back customers depending on the amount of month between canceled_date_1 and created_date_2
--If the interruption_period_1 column has value > 1, this is the win-back customer.
CTE12 AS
(
SELECT customer_id, created_date_1 as created_date, canceled_date_1 AS canceled_date, 'WIN-BACK' AS CUSTOMER_COHORT 
FROM CTE9
WHERE interruption_period_1 > 1

UNION ALL

SELECT customer_id, created_date_2 as created_date, canceled_date_2 AS canceled_date, 'WIN-BACK' AS CUSTOMER_COHORT 
FROM CTE9
WHERE interruption_period_1 > 1
)
,

--This CTE compiles customer IDs with two-time re-subscriptions into a single row.
CTE20 AS
(
SELECT customer_id, created_date_1 AS created_date, canceled_date_3 as canceled_date,'RETENTION' AS CUSTOMER_COHORT
FROM CTE9
WHERE interruption_period_1 IN (0,1)
	  AND 
	  interruption_period_2 IN (0,1)
--ORDER BY customer_id
)
,

--This CTE has win-back customers depending on the amount of month between canceled_date_2 and created_date_3,
--If the interruption_period_2 column has value > 1, this is the win-back customer.
--**TAKE NOTE: MINUS TWO ROWS DUE TO CTE11
CTE13 AS
(
SELECT customer_id, created_date_3 as created_date, canceled_date_3 as canceled_date, 'WIN-BACK' AS CUSTOMER_COHORT
FROM CTE9
WHERE interruption_period_2 > 1
)
,

--This CTE that has all win-back customers
CTE14 AS
(
SELECT *
FROM CTE12

UNION ALL

SELECT *
FROM CTE13
)
,

--This CTE has all retention customers
CTE15 AS
(
SELECT * 
FROM CTE10

UNION ALL

SELECT *
FROM CTE11
)
--SELECT COUNT(DISTINCT customer_id)
--SELECT COUNT (*)
--FROM CTE11
,

--**TAKE NOTE (Special Circumtance) This CTE shows the customer that has value of interruption_1 < 0 and this is a retention customer
CTE16 AS 
(
SELECT customer_id, created_date_1 as created_date, canceled_date_1 as canceled_date, 'RETENTION' AS CUSTOMER_COHORT
FROM CTE9
--WHERE created_date_3 != 0
--WHERE customer_id = 209743418
WHERE interruption_period_1 < 0
) 
,

--This CTE returns the table that has all duplicate customers after cleaning from CTE10, 11, 16, 20
CTE17 AS
(
SELECT customer_id, created_date, canceled_date, CUSTOMER_COHORT
FROM CTE10

UNION ALL

SELECT *
FROM CTE11

UNION ALL

SELECT *
FROM CTE16

UNION ALL

SELECT * 
FROM CTE20
)

/*DEAL WITH DUPLICATE CUSTOMER*/
,

--This CTE includes all customers who have subscribed once. (not re-subscription customer)
CTE18 AS
(
SELECT *
FROM CTE1
WHERE customer_id NOT IN (SELECT customer_id FROM CTE2)
)
,

--This CTE is used to calculate month span of the customers who have subscribes once (not re-subscription customer).
CTE19 AS
(
SELECT  *,
		39 as subscription_cost,
		'month' as subscription_interval,
		'Yes' as was_subscription_paid,
		DATEFROMPARTS(YEAR(created_date), MONTH(created_date), 01) AS 'Created Date (SOM)',
		COUNT(customer_id) OVER (PARTITION BY customer_id ORDER BY created_date, canceled_date) as OCCURENCES,
		--This is the way to calculate "month span"
		DATEDIFF(MONTH, created_date, canceled_date) 
		+
		CASE 
			WHEN created_date = canceled_date THEN 1
			WHEN DAY(created_date) < DAY(canceled_date) THEN 1
			ELSE 0
		END
		AS 'Month Span'	
FROM CTE17
--WHERE DAY(created_date) = DAY(canceled_date)
)
,

--This CTE has all duplicate customers after cleaning and the Month Span column has been added to the table.
CTE21 AS
(
SELECT *, 39 AS subscription_cost, 'month' AS subscription_interval, 'Yes' AS was_subscription_paid,
		    DATEFROMPARTS(YEAR(created_date), MONTH(created_date), 01) AS 'Created Date (SOM)',
			COUNT(customer_id) OVER (PARTITION BY customer_id ORDER BY created_date, canceled_date) AS OCCURENCES,
			DATEDIFF(MONTH, created_date, canceled_date)
			+
			CASE 
						WHEN created_date = canceled_date THEN 1
						WHEN DAY(created_date) < DAY(canceled_date) THEN 1
						ELSE 0
			END
			AS 'Month Span'				
FROM CTE12

UNION ALL 

SELECT * 
FROM CTE19
)
,

--DUPLICATE CUSTOMERS TABLE IS READY FOR ANALYZING
CTE22 AS
(
SELECT customer_id, created_date, canceled_date, subscription_cost, subscription_interval, was_subscription_paid,
	   [Created Date (SOM)], [Month Span]
FROM CTE21
)
,

--ONE-TIME SUBSCRIPTION CUSTOMERS TABLE IS READY FOR ANALYZING
CTE23 AS
(
SELECT *,
	   DATEFROMPARTS(YEAR(created_date), MONTH(created_date), 01) AS 'Created Date (SOM)',
	   DATEDIFF(MONTH, created_date, canceled_date)
	   +
	   CASE
			WHEN created_date = canceled_date THEN 1
			WHEN DAY(created_date) < DAY(canceled_date) THEN 1
			ELSE 0
	   END
	   AS 'Month Span'
FROM CTE1
WHERE customer_id NOT IN (SELECT customer_id FROM CTE2)
)
,

--THE DATA SET IS READY FOR ANALYSIS (CORE)
CTE24 AS
(
SELECT *
FROM CTE22

UNION ALL

SELECT *
FROM CTE23
)

SELECT *
FROM CTE24
--where customer_id = 155167073
/*
TO NAVIGATE CTE?
	LINE 6 FOR CTE1
	LINE 17 FOR CTE2
	LINE 27 FOR CTE3
	LINE 38 FOR CTE4
	LINE 47 FOR CTE5
	LINE 56 FOR CTE6
	LINE 65 FOR CTE7
	LINE 80 FOR CTE8
	LINE 126 FOR CTE9
	LINE 141 FOR CTE10
	LINE 153 FOR CTE11
	LINE 166 FOR CTE12
	LINE 195 FOR CTE13
	LINE 204 FOR CTE14
	LINE 217 FOR CTE15
	LINE 233 FOR CTE16
	LINE 244 FOR CTE17
	LINE 268 FOR CTE18
	LINE 277 FOR CTE19
	LINE 181 FOR CTE20
	LINE 300 FOR CTE21
	LINE 323 FOR CTE22
	LINE 331 FOR CTE23
	LINE 350 FOR CTE24

*/
