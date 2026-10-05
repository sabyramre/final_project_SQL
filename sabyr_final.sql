SELECT * FROM customers;
SELECT * FROM transactions;


-- Список клиентов с непрерывной историей за год, то есть каждый месяц на регулярной основе без пропусков за указанный годовой период, 
-- средний чек за период с 01.06.2015 по 01.06.2016, средняя сумма покупок за месяц, 
-- количество всех операций по клиенту за период;информацию в разрезе месяцев:

# Создаем временную таблицу на основе transactions для фильтра по датам, далее будем использовать именно ее
CREATE TEMPORARY TABLE transactions_period AS
(
	SELECT 
		* 
    FROM
		transactions
	WHERE date_new BETWEEN '2015-06-01' AND '2016-06-01'
);


# Создадим временную таблицу с клиентами, которые каждый месяц совершали хотя бы одну покупку
CREATE TEMPORARY TABLE client_continuous AS 
(
	SELECT 
		id_client,
		COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS month_count # переводим в формат "Год-месяц" для удобства, и чтобы одинаковые месяцы в разных года не схлопывались
	FROM
		transactions_period
	GROUP BY id_client
	HAVING COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) = 13 # Ставим 13, так как у нас период с июня 15го года до июня 16го года включительно 
);

# Далее делаем запрос, в котором выводим средний чек за период, среднюю сумму платежа за месяц и количество всех операции по этим клиентам
SELECT 
	c.id_client,
	SUM(t.Sum_payment) / COUNT(DISTINCT t.id_check) AS avg_bill_15_16, # Средний чек за период в год
	SUM(t.Sum_payment) / 13 AS avg_payment_month, # Средняя сумма покупки за месяц, для удобства всю сумму так же делим на 13
	COUNT(DISTINCT t.id_check) AS all_operations # Я определил один чек как одну операцию, поэтому просто считаем количество уникальных чеков
FROM
	transactions_period t
	JOIN client_continuous c
		ON t.id_client = c.id_client
GROUP BY 
	c.id_client;
    
    
# Следующий запрос, в котором та же информация, но с разбивкой по месяцам
SELECT 
	c.id_client,
    DATE_FORMAT(t.date_new, '%Y-%m') AS date_new, # Новый формат даты для группировки
	SUM(t.Sum_payment) / COUNT(DISTINCT t.id_check) AS avg_bill_month, # Средний чек за период в месяц
	SUM(t.Sum_payment) AS payment_month, # Сумма покупки за месяц
	COUNT(DISTINCT t.id_check) AS all_operations # количество уникальных чеков за месяц
FROM
	transactions_period t
	JOIN client_continuous c
		ON t.id_client = c.id_client
GROUP BY 
	c.id_client, DATE_FORMAT(t.date_new, '%Y-%m');



-- средняя сумма чека в месяц;
-- среднее количество операций в месяц;
-- среднее количество клиентов, которые совершали операции;
-- долю от общего количества операций за год и долю в месяц от общей суммы операций;
-- вывести % соотношение M/F/NA в каждом месяце с их долей затрат;


# Создаем временную таблицу для агрегации колонок с разбивкой по месяцам
# Также чтобы  получть среднее количество клиентов, которые совершали операции, просто берем клиентов из таблицы транзакций, т.к. в этой таблице все совершали операции

CREATE TEMPORARY TABLE month_agg AS
(
	SELECT 
		DATE_FORMAT(date_new, '%Y-%m') AS months, 
		SUM(sum_payment) AS sum_payment, 
		COUNT(DISTINCT id_check) AS check_count,
		COUNT(DISTINCT id_client) AS client_count
	FROM 
		transactions_period
	GROUP BY DATE_FORMAT(date_new, '%Y-%m')
);


SELECT
	SUM(sum_payment) / SUM(check_count) AS avg_payment_per_month, # средняя сумма чека в месяц
    AVG(check_count) AS avg_checks_per_month, # среднее количество операций в месяц
    AVG(client_count) AS avg_clients_per_month # среднее количество клиентов, которые совершали операции
FROM
	month_agg;


# Доля каждого месяца в процентах от общего количества операций и общей суммы операций
SELECT 
	months,
	check_count / SUM(check_count) OVER() * 100.0 AS check_rate_per_month,
    sum_payment / SUM(sum_payment) OVER() * 100.0 AS payment_rate_per_month
FROM
	month_agg;


# Для определения долей затрат гендеров, нужно заменить NULL значения на NA в колонке Gender
UPDATE customers
SET Gender = 'NA'
WHERE Gender IS NULL;


# CTE с разбивкой по месяцам и гендеру, в котором считаем количество клиентов и общую сумму
WITH gender_rate AS
(
	SELECT 
		DATE_FORMAT(t.date_new, '%Y-%m') AS months,
		c.gender,
        COUNT(DISTINCT t.id_client) AS client_count,
		SUM(t.Sum_payment) AS Sum_payment
	FROM
		transactions_period t
		JOIN customers c
			ON t.id_client = c.id_client
	GROUP BY
		DATE_FORMAT(t.date_new, '%Y-%m'), c.gender
)

# Во внешнем запросе получаем соотношение полов в каждом месяце и их долю платежей в каждом месяце
SELECT 
	months,
    gender,
    client_count / SUM(client_count) OVER(PARTITION BY months) * 100 AS gender_rate, # соотношение полов
    Sum_payment / SUM(Sum_payment) OVER(PARTITION BY months) * 100 AS payment_rate # доля платежей
FROM 
	gender_rate;
    
    
-- возрастные группы клиентов с шагом 10 лет и отдельно клиентов, у которых нет данной информации, 
-- с параметрами сумма и количество операций за весь период, и поквартально - средние показатели и %.


# Временная таблица для распределения клиентов по возрастным группам
CREATE TEMPORARY TABLE age_groups AS
(
	SELECT 
		id_client,
		AGE,
		CASE
			WHEN AGE IS NULL THEN 'NA'
			WHEN AGE < 10 THEN '0-9'
			WHEN AGE BETWEEN 10 AND 19 THEN '10-19'
			WHEN AGE BETWEEN 20 AND 29 THEN '20-29'
			WHEN AGE BETWEEN 30 AND 39 THEN '30-39'
			WHEN AGE BETWEEN 40 AND 49 THEN '40-49'
			WHEN AGE BETWEEN 50 AND 59 THEN '50-59'
			WHEN AGE BETWEEN 60 AND 69 THEN '60-69'
			WHEN AGE BETWEEN 70 AND 79 THEN '70-79'
			WHEN AGE BETWEEN 80 AND 89 THEN '80-89'
			WHEN AGE >= 90 THEN '90+'
		END AS age_group
	FROM customers
);

# Распределив клиентов по группам, в следующем запросе мы получаем сумму платежей и общее количество операций (чеков) по этим группам, соединив с таблицей транзакций
SELECT 
	a.age_group,
    SUM(t.Sum_payment) AS Sum_payment,
    COUNT(DISTINCT id_check) AS total_check
FROM age_groups a
	JOIN transactions_period t
		ON a.id_client = t.id_client
GROUP BY a.age_group
ORDER BY a.age_group;


# СТЕ для агрегаций колонок с разбивкой по возрастным группам
# Чтобы разбить также по кварталам, добавил колонку date_year, чтобы одинаковые кварталы из двух разных годов не схлопывались 
WITH groups_agg AS
(
	SELECT 
		a.age_group,
        YEAR(t.date_new) AS date_year,
		QUARTER(t.date_new) AS qrtr,
        SUM(t.sum_payment) sum_payment,
        COUNT(DISTINCT t.id_check) count_check,
        COUNT(DISTINCT t.id_client) count_client,
        COUNT(DISTINCT DATE_FORMAT(t.date_new, '%Y-%m')) AS month_count
	FROM
		age_groups a
        JOIN transactions_period t
			ON a.id_client = t.id_client
	GROUP BY
		a.age_group,
        YEAR(t.date_new),
		QUARTER(t.date_new)
        
)
# Во внешнем запросе получаем средние показатели для групп поквартально.
SELECT
	date_year,
    qrtr,
    age_group,
    sum_payment / month_count AS avg_payment_per_month, # Средняя сумма покупок в месяц
    count_check / month_count AS avg_check_per_month, # Cреднее количество операций в месяц
    count_client / month_count AS avg_client_per_month, # Среднее количество клиентов в месяц
    sum_payment / count_check AS avg_payment, # Cредний чек
    count_check / SUM(count_check) OVER(PARTITION BY date_year, qrtr) * 100.0 AS check_rate, # Доля количества операций для групп по кварталам
    sum_payment / SUM(sum_payment) OVER(PARTITION BY date_year, qrtr) * 100.0 AS payment_rate # Доля суммы для групп по кварталам
FROM groups_agg
ORDER BY 
	date_year, 
    qrtr,
    age_group;



