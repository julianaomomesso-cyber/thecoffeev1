-- =====================================================================
-- Vendas de 2026-08-01 a 2026-08-31 — loja 407
-- Origem: vendas_agosto.csv
-- Cole o arquivo inteiro no SQL Editor do Supabase e rode.
-- Pode rodar de novo no mesmo periodo: a chave faz upsert, nao duplica.
-- =====================================================================
do $$
declare v_imp bigint; r record;
begin
  insert into ops.venda_importacoes (loja_id,origem,ref_externa,de,ate)
  values (407,'planilha_looker','vendas_agosto.csv','2026-08-01','2026-08-31') returning id into v_imp;

  insert into ops.venda_staging (importacao_id,linha,nome_produto,categoria,qtd,receita)
  select v_imp, v.linha, v.nome, v.cat, v.qtd, v.rec
  from (values (2,'Hot Drip V60','Methods',17.0,290.3),
           (3,'Ragù Sandwich','Brunch All Day',7.0,272.35),
           (4,'Fresh Orange Juice','Brunch All Day',12.0,242.04),
           (5,'Cake of the day','Foods',11.0,232.14),
           (6,'Ichigo Matcha','Signature Beverages',9.0,212.42),
           (7,'Combo Osaka','Brunch All Day',3.0,209.72),
           (8,'Avocado Toast','Brunch All Day',6.0,215.4),
           (9,'True White','Purist Drinks',11.0,211.3),
           (10,'Cheese bread','Foods',15.0,173.41),
           (11,'Chicken Katsu Sando','Brunch All Day',5.0,167.52),
           (12,'Iced Vanilla','Signature Beverages',7.0,136.26),
           (13,'Iced Blueberry Matcha','Seasonal Drinks',6.0,157.02),
           (14,'Americano','Purist Drinks',10.0,108.5),
           (15,'Croissant filled with cheese','Foods',6.0,132.09),
           (16,'Mad Mocha','Signature Beverages',7.0,149.0),
           (17,'Banana Cake','Foods',9.0,143.55),
           (18,'Eggs Benedict','Brunch All Day',4.0,143.6),
           (19,'Nutty Latte (Signature)','Signature Beverages',7.0,139.0),
           (20,'Grilled Ham & Cheese Sandwich','Foods',6.0,117.95),
           (21,'Pancake with Fruits and Honey','Brunch All Day',4.0,115.95),
           (22,'Pure Black (Double Shot)','Purist Drinks',9.0,116.0),
           (23,'Grilled Cheese Sandwich','Foods',6.0,124.7),
           (24,'Tiramisu Latte (Signature)','Signature Beverages',6.0,119.4),
           (25,'Croissant Traditional','Foods',7.0,114.92),
           (26,'Combo Tokyo','Brunch All Day',2.0,94.24),
           (27,'Honey Egg Croissant','Brunch All Day',5.0,110.45),
           (28,'Omelet toast - BR','Brunch All Day',4.0,106.22),
           (29,'Iced Chocolate','Signature Beverages',5.0,107.5),
           (30,'Omelet Bacon Sandwich','Brunch All Day',3.0,94.94),
           (31,'Iced Mocha','Signature Beverages',4.0,87.46),
           (32,'Ham and Eggs','Brunch All Day',3.0,98.7),
           (33,'Flat Caramel','Signature Beverages',4.0,92.22),
           (34,'Matcha Tonka Iced Latte','Signature Beverages',4.0,94.0),
           (35,'Cookie Traditional','Foods',6.0,72.97),
           (36,'Chai Latte','Purist Drinks',4.0,81.0),
           (37,'Still Mineral Water','Other Beverages',10.0,89.0),
           (38,'Salted Caramel','Signature Beverages',3.0,64.06),
           (39,'Yogurt Granola Bowl','Foods',3.0,61.2),
           (40,'Gelato Frappé Coffee','Gelato Frappés',3.0,68.85),
           (41,'Tonka Latte','Signature Beverages',3.0,65.98),
           (42,'Gelato Frappé Chocolate','Gelato Frappés',3.0,64.53),
           (43,'Sparkling Water','Other Beverages',8.0,62.3),
           (44,'Classic Caesar Salad','Brunch All Day',2.0,48.86),
           (45,'Apple Maple Latte (Signature)','Signature Beverages',3.0,64.4),
           (46,'Cheese bread with cream cheese','Foods',5.0,67.5),
           (47,'Croissant filled with cheese and cured ham','Foods',2.0,54.9),
           (48,'Stuffed Cheese Bread','Foods',4.0,59.6),
           (49,'Brownie','Foods',4.0,58.0),
           (50,'Sun-dried Tomato, Pesto & Cheese Sando','Foods',2.0,47.43),
           (51,'Matcha Iced Latte','Purist Drinks',2.0,41.03),
           (52,'Gelato Frappé Mocha','Gelato Frappés',2.0,53.0),
           (53,'Macadamia Cookie','Foods',3.0,45.15),
           (54,'Matcha Tonic','Signature Beverages',2.0,43.34),
           (55,'Matcha Vanilla Latte','Signature Beverages',2.0,47.5),
           (56,'Macchiato','Purist Drinks',3.0,46.5),
           (57,'Iced Spanish Latte','Purist Drinks',2.0,45.8),
           (58,'Pain au Chocolat','Foods',2.0,43.0),
           (59,'Urban Chocolate','Signature Beverages',2.0,42.3),
           (60,'Cookie Triple Chocolate','Foods',3.0,41.7),
           (61,'Vanilla Latte','Signature Beverages',2.0,39.0),
           (62,'Caramel Bar','Brunch All Day',2.0,22.93),
           (63,'Buffalo Mozzarella and Arugula','Brunch All Day',1.0,28.72),
           (64,'Croissant filled with ricotta and honey','Foods',1.0,31.9),
           (65,'Salted Caramel Cookie','Foods',2.0,31.0),
           (66,'Iced Latte','Purist Drinks',1.0,16.49),
           (67,'Gelato Frappé Chai','Gelato Frappés',1.0,27.5),
           (68,'Omelet Cheese Sandwich','Foods',1.0,21.52),
           (69,'Matcha Latte','Purist Drinks',1.0,25.4),
           (70,'Fruits Salad','Foods',1.0,12.82),
           (71,'Spanish Latte','Purist Drinks',1.0,20.9),
           (72,'Fresh Soda Strawberry','Fresh Soda',1.0,20.5),
           (73,'Fresh Soda Pink Lemonade','Fresh Soda',1.0,20.5),
           (74,'Red Juice','Other Beverages',1.0,13.93),
           (75,'Brigadeiro','Foods',2.0,16.83),
           (76,'Espresso Tonic','Purist Drinks',1.0,18.9),
           (77,'Buttered Toast','Brunch All Day',1.0,17.9)
       ) as v(linha,nome,cat,qtd,rec);

  select * into r from ops.processar_importacao(v_imp);
  raise notice 'lote %: % produtos amarrados, % orfaos, % itens sem ficha',
    v_imp, r.produtos_ok, r.produtos_orfaos, r.itens_orfaos;
end $$;

-- O que a planilha trouxe e o sistema nao reconheceu.
-- Enquanto esta lista nao esvaziar, o CMV esta subestimado.
select nome_produto, categoria, qtd, receita
from   ops.v_import_orfaos
where  importacao_id = (select max(id) from ops.venda_importacoes)
order  by qtd desc;
