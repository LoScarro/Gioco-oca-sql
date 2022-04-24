SET search_path to oca;

-- INTERROGAZIONI CARICO DI LAVORO
-- 1: Determinare l’identificatore dei giochi che coinvolgono al più quattro squadre e richiedono l’uso di due dadi. 

	SELECT IdGioco 
	FROM Gioco 
	WHERE NumeroDadi = 2 AND MaxSquadre <= 4; 
	
-- 2: Determinare l’identificatore delle sfide relative a un gioco A di vostra scelta (specificare direttamente l’identificatore nella richiesta) che, in alternativa: 
-- o hanno avuto luogo a gennaio 2021 e durata massima superiore a 2 ore, o hanno avuto luogo a marzo 2021 e durata massima pari a 30 minuti. 


-- Con "Hanno avuto luogo a [gennaio/marzo]" si intendono sfide che possono essere iniziate o finite anche in periodi adiacenti ma si sono svolte almeno in parte a gennaio o marzo
	SELECT IdSfida 
	FROM Sfida  
	WHERE IdGioco = 1 AND ((((DataOraInizio BETWEEN '2021-01-01 00:00:00' AND '2021-01-31 23:59:59') OR (DataOraFine BETWEEN '2021-01-01 00:00:00' AND '2021-01-31 23:59:59')) AND Durata_Max > '02:00:00')  
							OR (((DataOraInizio BETWEEN '2021-03-01 00:00:00' AND '2021-03-31 23:59:59') OR (DataOraFine BETWEEN '2021-03-01 00:00:00' AND '2021-03-31 23:59:59')) AND Durata_Max = '00:30:00'));

-- 3: Determinare le sfide, di durata massima superiore a 2 ore, dei giochi che richiedono almeno due dadi. 
-- Restituire sia l’identificatore della sfida sia l’identificatore del gioco. 

	SELECT IdSfida, IdGioco 
	FROM Sfida NATURAL JOIN Gioco 
	WHERE NumeroDadi >= 2 AND Durata_Max > 120 

-- 1 VISTA
-- La definizione di una vista che fornisca alcune informazioni riassuntive per ogni gioco: il numero di sfide relative a quel gioco disputate, la durata media di tali sfide, 
-- il numero di squadre e di giocatori partecipanti a tali sfide, i punteggi minimo, medio e massimo ottenuti dalle squadre partecipanti a tali sfide

	CREATE VIEW infoGioco AS
	SELECT *
	FROM 
		(SELECT IdGioco, COUNT(DISTINCT IdSfida) AS NumeroSfide, COUNT(DISTINCT (Nome, IdSfida)) AS NumeroSquadre, COUNT(DISTINCT(ID, Email)) AS NumeroUtenti
		 FROM Sfida NATURAL JOIN Squadra NATURAL JOIN Utente
		 GROUP BY IdGioco) A
		 
		NATURAL JOIN
	
		(SELECT IdGioco, AVG(DataOraFine - DataOraInizio) AS durataMediaSfide
		 FROM Sfida
		 GROUP BY IdGioco) B
		
		NATURAL JOIN
		
		(SELECT IdGioco, MIN(punteggio) AS punteggiominimo, AVG(punteggio) AS punteggiomedio, MAX(punteggio) AS punteggiomassimo
		 FROM Sfida NATURAL JOIN Squadra
		 GROUP BY IdGioco) C;
		
	SELECT * FROM infogioco;

-- 2 INTERROGAZIONI AGGIUNTIVE
-- a. Determinare i giochi che contengono caselle a cui sono associati task;
	
	SELECT DISTINCT IdGioco
	FROM Casella
	WHERE Task IS NOT NULL;
	
-- b. Determinare i giochi che non contengono caselle a cui sono associati task;

	SELECT IdGioco FROM Gioco
	
	EXCEPT
	
	SELECT DISTINCT IdGioco
	FROM Casella
	WHERE Task IS NOT NULL;
	
-- c. Determinare le sfide che hanno durata superiore alla durata media delle sfide relative allo stesso gioco

	SELECT S.IdSfida
	FROM Sfida S
	WHERE (S.DataOraFine IS NOT NULL AND (S.DataOraFine - S.DataOraInizio) > (SELECT AVG(Sfida.DataOraFine-Sfida.DataOraInizio)
																				FROM Sfida
																				WHERE Sfida.IdGioco = S.IdGioco
																				GROUP BY Sfida.IdGioco
																			  ))
			OR (S.DataOraFine IS NULL AND (CURRENT_DATE - S.DataOraInizio) > (SELECT AVG(Sfida.DataOraFine-Sfida.DataOraInizio)
																				FROM Sfida
																				WHERE Sfida.IdGioco = S.IdGioco
																				GROUP BY Sfida.IdGioco
																			  ));

-- 3 FUNZIONI
-- a. Funzione che realizza l’interrogazione 2c in maniera parametrica rispetto all’ID del gioco (cioè determina le sfide che hanno durata superiore alla durata medie 
-- delle sfide di un dato gioco, prendendo come parametro l’ID del gioco);

CREATE OR REPLACE FUNCTION sfideLunghe(IN gioco INTEGER)
RETURNS TABLE (IdSfida INTEGER) AS
$sfideLunghe$
	BEGIN
		RETURN QUERY (SELECT S.IdSfida
					  FROM Sfida S
					  WHERE (S.DataOraFine IS NOT NULL AND (S.DataOraFine - S.DataOraInizio) > (SELECT AVG(Sfida.DataOraFine-Sfida.DataOraInizio)
																								FROM Sfida
																								WHERE Sfida.IdGioco = gioco
																								GROUP BY Sfida.IdGioco
																							  ))
							  OR (S.DataOraFine IS NULL AND (CURRENT_DATE - S.DataOraInizio) > (SELECT AVG(Sfida.DataOraFine-Sfida.DataOraInizio)
																								FROM Sfida
																								WHERE Sfida.IdGioco = gioco
																								GROUP BY Sfida.IdGioco
																							  ))
					 );
	END;
$sfideLunghe$ LANGUAGE plpgsql;

SELECT * FROM sfideLunghe(1);

-- b. Funzione di scelta dell’icona da parte di una squadra in una sfida: possono essere scelte solo le
-- icone corrispondenti al gioco cui si riferisce la sfida che non siano già state scelte da altre squadre.

CREATE OR REPLACE FUNCTION sceltaIcona(IN nomeSquadra VARCHAR(30), IN sfida INTEGER)
RETURNS TABLE (NomeIcona VARCHAR(20)) AS
$sceltaIcona$
	DECLARE
		idGiocoSquadra INTEGER;
	BEGIN
		SELECT IdGioco INTO idGiocoSquadra
		FROM Sfida
		WHERE IdSfida = sfida;
		
		RETURN QUERY (SELECT Icona.nome 
					  FROM Icona JOIN Seticone ON Icona.set = Seticone.nome JOIN Gioco ON Gioco.seticone = seticone.nome
					  WHERE IdGioco = idGiocoSquadra
					  
					  EXCEPT
					  
					  SELECT nomeicona FROM Squadra
					  WHERE IdSfida = sfida AND nome <> nomeSquadra
					 );
	END;
$sceltaIcona$ LANGUAGE plpgsql;

-- 4 TRIGGER

-- a. Verifica del vincolo che nessun utente possa partecipare a sfide contemporanee;

CREATE OR REPLACE FUNCTION controlloUtenti()
RETURNS TRIGGER AS
$controlloUtenti$
	BEGIN
		IF( EXISTS (SELECT *
					FROM Utente NATURAL JOIN Squadra NATURAL JOIN Sfida
					WHERE email = NEW.email AND dataOraFine IS NULL))
		THEN 
			RAISE NOTICE 'Utente % sta già partecipando ad una sfida', NEW.email;
			RETURN NULL;
		ELSE
			RETURN NEW;
		END IF;
	END;
$controlloUtenti$ LANGUAGE plpgsql;

CREATE TRIGGER sfideContemporanee
BEFORE INSERT OR UPDATE OF Nome, IdSfida ON Utente
FOR EACH ROW
EXECUTE PROCEDURE controlloUtenti();

-- b. Mantenimento del punteggio corrente di ciascuna squadra in ogni sfida e inserimento delle icone opportune nella casella podio.

-- Trigger per mantenimento punteggio corrente squadra

CREATE OR REPLACE FUNCTION aggiornaPunteggio()
RETURNS TRIGGER AS
$aggiornaPunteggio$	
	BEGIN
		
		
	END;
$aggiornaPunteggio$ LANGUAGE plpgsql;

CREATE TRIGGER classifica
AFTER INSERT OR UPDATE OF punteggioTurno ON Turno
FOR EACH ROW
EXECUTE PROCEDURE aggiornaPunteggio();

-- Trigger per aggiornamento podio

CREATE OR REPLACE FUNCTION aggiornaClassifica()
RETURNS TRIGGER AS
$aggiornaClassifica$
	BEGIN
	
	END;
$aggiornaClassifica$ LANGUAGE plpgsql;

CREATE TRIGGER aggiornaClassifica
AFTER INSERT OR UPDATE OF punteggio ON Squadra
EXECUTE PROCEDURE aggiornaClassifica();
