-- Creazione schema OCA

CREATE schema oca;
SET search_path to oca;
set datestyle to 'DMY'; 

-- Creazione tipi enum per attributi di Utente e Casella
CREATE TYPE tipoCasella AS ENUM ('start', 'arrivo', 'standard', 'speciale');
CREATE TYPE tipoUtente AS ENUM ('coach', 'caposquadra');
CREATE TYPE ruoloUtente AS ENUM ('giocatore', 'moderatore', 'giocatore e moderatore');

-- Creazione tabelle Sfida, Gioco, Squadra, Anagrafica_Utente, Utente, Turno, Casella, Ha_Quiz, Task, Immagine, Quiz, SetIcone, Icona, Podio

-- IMMAGINE (ID_Immagine, Sfondo) 
CREATE TABLE Immagine
	(
		IDImmagine SERIAL PRIMARY KEY,
		Sfondo BOOLEAN NOT NULL default false
	);
	
-- TASK (ID Task, Punteggio Task, Testo) 
CREATE TABLE Task
	(
		IDTask SERIAL PRIMARY KEY,
		PunteggioTask NUMERIC(3) NOT NULL,
		Testo TEXT NOT NULL
	);
	
-- ANAGRAFICA_UTENTE (E-mail, Nickname, Nome(o), Cognome(o), DataN(o)) 
CREATE TABLE AnagraficaUtente
	(
		Email VARCHAR(30) PRIMARY KEY,
		Nickname VARCHAR(20) NOT NULL,
		Nome VARCHAR(20),
		Cognome VARCHAR(20),
		DataN DATE
	);

-- SET_ICONE (Nome) 
CREATE TABLE SetIcone
	(
		Nome VARCHAR(20) PRIMARY KEY
	);

-- ICONA (Nome, Tema, Dimensione, Set(SET_ICONE))
CREATE TABLE Icona
	(
		Nome VARCHAR(20) PRIMARY KEY, 
		Tema VARCHAR(20) NOT NULL,
		Dimensione CHAR(7) NOT NULL default '256x256' CHECK(Dimensione='256x256'),
		Set VARCHAR(20) REFERENCES SetIcone ON UPDATE CASCADE NOT NULL
	);

-- GIOCO (IdGioco, MaxSquadre, NumeroDadi, ID_Immagine(IMMAGINE), SetIcone(SET_ICONE))
CREATE TABLE Gioco
	(
		IdGioco SERIAL PRIMARY KEY,
		MaxSquadre NUMERIC(2) NOT NULL,
		NumeroDadi NUMERIC(2) NOT NULL,
		IdImmagine INTEGER references Immagine NOT NULL,
		SetIcone VARCHAR(20) references SetIcone NOT NULL,
		Dummy TEXT NOT NULL,
		CONSTRAINT not_negative CHECK (MaxSquadre>0 AND NumeroDadi>=0)
	);

-- PODIO (Pos, IdGioco(GIOCO), X, Y) 
CREATE TABLE Podio
	(
		IdGioco INTEGER REFERENCES Gioco,
		Pos NUMERIC(1) NOT NULL CHECK(Pos>=1 AND Pos<=3),
		X NUMERIC(4,2) NOT NULL,
		Y NUMERIC(4,2) NOT NULL,
		UNIQUE (IdGioco, X, Y),
		PRIMARY KEY (Pos, IdGioco)
	);

-- SFIDA (IDSfida, DataOraInizio, DataOraFine(O), Moderata, Durata_Max, IdGioco(GIOCO))
CREATE TABLE Sfida
	(
		IdSfida SERIAL PRIMARY KEY,
		DataOraInizio TIMESTAMP NOT NULL default CURRENT_DATE,
		DataOraFine TIMESTAMP,
		Moderata BOOLEAN default false NOT NULL,
		Durata_Max INTERVAL NOT NULL,
		IdGioco INTEGER references Gioco NOT NULL,
		Dummy TEXT NOT NULL,
		CONSTRAINT dataOraEsatte CHECK (dataOraFine IS NULL OR dataOraFine > dataOraInizio),
		CONSTRAINT durataMassima CHECK (dataOraFine IS NULL OR (dataOraFine - dataOraInizio) <= Durata_Max)
	);

-- SQUADRA (Nome, IDSfida(SFIDA), NomeIcona(ICONA), Punteggio, Pos(PODIO)o, IdGioco(PODIO)o) 
CREATE TABLE Squadra
	(
		Nome VARCHAR(30),
		IdSfida INTEGER references Sfida,
		NomeIcona VARCHAR(20) references Icona NOT NULL,
		Punteggio NUMERIC(3),
		Pos NUMERIC(1),
		IdGioco INTEGER,
		FOREIGN KEY (Pos, IdGioco) REFERENCES Podio,
		PRIMARY KEY (Nome, IdSfida),
		UNIQUE(IdSfida, NomeIcona)
	);

-- UTENTE (ID, Email(ANAGRAFICA_UTENTE), Tipo(o), Ruolo, Nome(SQUADRA), IDSfida(SQUADRA))
CREATE TABLE Utente
	(
		ID BIGSERIAL,
		Email VARCHAR(30) references AnagraficaUtente ON UPDATE CASCADE,
		Tipo tipoUtente,
		Ruolo ruoloUtente NOT NULL default 'giocatore',
		Nome VARCHAR(30) NOT NULL,
		IdSfida INTEGER NOT NULL,
		PRIMARY KEY(ID, Email),
		FOREIGN KEY(Nome, IdSfida) references Squadra
	);
	
-- CASELLA (IdGioco(GIOCO), NumeroOrdine, Tipologia, Video(O), Destinazione(O), Task(TASK)o, X, Y) 
CREATE TABLE Casella
	(
		IdGioco INTEGER references Gioco,
		NumeroOrdine SERIAL,
		Tipologia tipoCasella NOT NULL default 'standard',
		Video VARCHAR(80),
		Destinazione INTEGER,
		Task INTEGER references Task,
		X NUMERIC(4, 2) NOT NULL,
		Y NUMERIC(4, 2) NOT NULL,
		PRIMARY KEY (IdGioco, NumeroOrdine),
		UNIQUE (IdGioco, X, Y)
	);

-- TURNO (Num, PunteggioTurno, Nome(SQUADRA), IdSfida(SQUADRA), IdGioco(CASELLA), NumeroOrdine(CASELLA))
CREATE TABLE Turno
	(
		Num SERIAL,
		PunteggioTurno NUMERIC(3) NOT NULL,
		Nome VARCHAR(30), 
		IdSfida INTEGER,
		IdGioco INTEGER NOT NULL,
		NumeroOrdine INTEGER NOT NULL,
		FOREIGN KEY (Nome, IdSfida) references Squadra,
		FOREIGN KEY (IdGioco, NumeroOrdine) references Casella,
		PRIMARY KEY (Num, Nome, IdSfida)
	);

-- QUIZ (ID Quiz, Testo, ID_Immagine(IMMAGINE)o) 
CREATE TABLE Quiz
	(
		IDQuiz SERIAL PRIMARY KEY,
		Testo TEXT NOT NULL,
		IDImmagine INTEGER REFERENCES Immagine
	);
	
-- HA_QUIZ (IdGioco(CASELLA), NumeroOrdine(CASELLA), IDQuiz(QUIZ)) 
CREATE TABLE HaQuiz
	(
		IdGioco INTEGER,
		NumeroOrdine INTEGER,
		IDQuiz INTEGER references Quiz,
		PRIMARY KEY (IdGioco, NumeroOrdine, IDQuiz),
		FOREIGN KEY (IdGioco, NumeroOrdine) references Casella
	);

-- CREAZIONE TRIGGER FONDAMENTALI PER POPOLAMENTO CORRETTO BASE DI DATI
CREATE OR REPLACE FUNCTION controlloTurnoCasella()
RETURNS TRIGGER AS
$controlloTurnoCasella$
	BEGIN
		
		IF (NEW.IdGioco <> (SELECT Sfida.IdGioco
							FROM Sfida JOIN Turno ON Sfida.IdSfida = Turno.IdSfida
							WHERE Turno.Num = NEW.Num AND Turno.Nome = NEW.Nome AND Turno.IdSfida = NEW.IdSfida))
		THEN
			RETURN NULL;
		ELSE
			RETURN NEW;
		END IF;
	END;
$controlloTurno$ LANGUAGE plpgsql;

CREATE TRIGGER controlloTurnoCasella
BEFORE INSERT OR UPDATE ON Turno
FOR EACH ROW
EXECUTE PROCEDURE controlloTurnoCasella();