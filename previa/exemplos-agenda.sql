insert into public.eventos (titulo, data, ministerio, lider, horario, horario_inicio, horario_fim, local, necessita_midia, necessita_louvor, necessita_diaconia, midia_tema, observacoes, bloqueado) values
 ('CULTO DE JOVENS','2026-12-05','Juventude Mergulhados','Ezequiel','19:30 às 21:30','19:30','21:30','Templo','Sim','Sim','Não','Natal Mergulhados','Trazer convidados',false),
 ('ENSAIO GERAL DE NATAL','2026-12-12','Louvor','','19h às 22h',null,null,'Templo, Salão de Festas','Não','Sim','Não',null,null,false),
 ('CONFERÊNCIA MERGULHADOS','2026-11-13','Juventude','Ezequiel','20:00 às 22:00','20:00','22:00','Templo','Sim','Sim','Sim','10 anos',null,false),
 ('CAFÉ DAS MULHERES','2026-12-19','Mulheres Betel','Ana','08:00 às 10:00','08:00','10:00','Salão de Festas','Sim','Não','Sim','Café',null,true),
 ('REUNIÃO GERAL','2026-12-20','Igreja',null,null,null,null,null,null,null,null,null,null,false);
insert into public.reservas (ministerio, motivo, espacos, data, horario_inicio, horario_fim, lote_id) values
 ('Louvor','Ensaio','Templo','2026-12-03','19:00','21:00','LOTE-1700000000000'),
 ('Louvor','Ensaio','Templo','2026-12-10','19:00','21:00','LOTE-1700000000000'),
 ('Louvor','Ensaio','Templo','2026-12-17','19:00','21:00','LOTE-1700000000000'),
 ('Kids','Reunião de pais','Quadra','2026-12-06','09:00','10:30',null);
