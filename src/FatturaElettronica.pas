unit FatturaElettronica;

interface uses Vcl.Forms;

function feGeneraFatturaElettronica(xmlFileName : string; owner : TForm; idDocumento : integer) : boolean;


implementation uses DatabaseCommon, XMLDoc, Xml.XMLIntf, Data.Win.ADODB, SysUtils, System.DateUtils, Vcl.Dialogs, System.Types, System.StrUtils;


function feAddFatturaElettronicaHeader(const XMLDoc: IXMLDocument; const iNodoLiv0 : IXMLNode) : boolean; forward;
function feAddFatturaElettronicaBody  (const XMLDoc: IXMLDocument; const iNodoLiv0 : IXMLNode) : boolean; forward;

var
  qryDatiImpresa    : TAdoQuery;
  qryDocumento      : TAdoQuery;
  qryDocumentoRighe : TAdoQuery;
  qryTipoDocumento  : TAdoQuery;
  qryAnagrafica     : TAdoQuery;


// ********************************************************
//
// CONNESSIONE CON DB
//
// ********************************************************

procedure feInitializeDBConnection;
begin
  // ...
  if qryDatiImpresa    <> nil then exit;
  if qryDocumento      <> nil then exit;
  if qryDocumentoRighe <> nil then exit;
  if qryTipoDocumento  <> nil then exit;
  if qryAnagrafica     <> nil then exit;

  // crea query ...
  qryDatiImpresa                   := TAdoQuery.Create(nil);
  qryDatiImpresa.connection        := dmDatabaseCommon.cnnSqlServer;
  dmDatabaseCommon.cnnSqlServer.ConnectionString;

  qryDocumento                     := TAdoQuery.Create(nil);
  qryDocumento.connection          := dmDatabaseCommon.cnnSqlServer;

  qryDocumentoRighe                := TAdoQuery.Create(nil);
  qryDocumentoRighe.connection     := dmDatabaseCommon.cnnSqlServer;

  qryTipoDocumento                 := TAdoQuery.Create(nil);
  qryTipoDocumento.connection      := dmDatabaseCommon.cnnSqlServer;

  qryAnagrafica                    := TAdoQuery.Create(nil);
  qryAnagrafica.connection         := dmDatabaseCommon.cnnSqlServer;
end;

procedure feFinalizeDBConnection;
begin
  // ...
  if qryDatiImpresa    = nil then exit;
  if qryDocumento      = nil then exit;
  if qryDocumentoRighe = nil then exit;
  if qryTipoDocumento  = nil then exit;
  if qryAnagrafica     = nil then exit;

  try
    qryDatiImpresa   .close;
    qryDocumento     .close;
    qryDocumentoRighe.close;
    qryTipoDocumento .close;
    qryAnagrafica    .close;

    qryDatiImpresa   .free;
    qryDocumento     .free;
    qryDocumentoRighe.free;
    qryTipoDocumento .free;
    qryAnagrafica    .free;
  except
  end;
end;


procedure feQuerySetup(const idDocumento : integer);

var
  idAnagrafica  : integer;
  tipoDocumento : string;

begin
  try
    // svuota query ...
    qryDatiImpresa   .SQL.clear;
    qryDocumento     .SQL.clear;
    qryDocumentoRighe.SQL.clear;
    qryTipoDocumento .SQL.clear;
    qryAnagrafica    .SQL.clear;

    // ...
    qryDatiImpresa   .SQL.add('SELECT * FROM TDatiImpresa');
    qryDocumento     .SQL.add('SELECT * FROM TDocumenti      WHERE ID='          + intToStr(idDocumento));

    // righe fattura
    qryDocumentoRighe.SQL.add('SELECT A.*, B.PercIva, B.Natura ');
    qryDocumentoRighe.SQL.add('FROM TDocumentiRighe as A ');
    qryDocumentoRighe.SQL.add('LEFT JOIN TIva as B ');
    qryDocumentoRighe.SQL.add('ON A.CodIva = B.CodIva ');
    qryDocumentoRighe.SQL.add('WHERE IDDocumento= ' + intToStr(idDocumento)+ ' ');
    qryDocumentoRighe.SQL.add('ORDER BY OrdinamentoRiga ');

//    // documenti di trasporto
//SELECT ID, TipoDocumento, IDAnagrafica, Data, Numero, Anno, [=== RIF. DOC ESTERNI ===], DataDocEsterni, NumDocEsterni, TTipiDocumento.NomeBreve
//FROM   TDocumenti
//
//INNER JOIN TTipiDocumento
//ON TDocumenti.TipoDocumento = TTipiDocumento.TipoDoc
//
//WHERE  InclusoInIDDoc IS NULL
//  AND  IDAnagrafica   = :idAnagrafica
//  AND  TipoDocumento in (
//          SELECT DISTINCT TipoDoc
//          FROM   TTipiDocumento
//          WHERE  IncludibileIn LIKE :tipoDocumento
//       )


    // ...
    qryDatiImpresa   .active := true;
    qryDocumento     .active := true;
    qryDocumentoRighe.active := true;

    // ...
    idAnagrafica := qryDocumento.fieldByName('IDAnagrafica').asInteger;

    // ...
    qryAnagrafica    .SQL.add('SELECT PecAziendale FROM TAnagrafica WHERE ID=' + intToStr(idAnagrafica));
    qryAnagrafica    .active := true;

    // ...
    tipoDocumento := qryDocumento.fieldByName('TipoDocumento').asString;

    // ...
    qryTipoDocumento .SQL.add('SELECT FatturaElettronicaTipoDocumento FROM TTipiDocumento WHERE TipoDoc=''' + tipoDocumento + '''');
    qryTipoDocumento .active := true;

  except
    on E : Exception do
      ShowMessage(E.ClassName+' error raised, with message : '+E.Message);
  end;
end;

function calcolaScontoDaFormula(const formula : string) : double;

var
  strArray     : TStringDynArray;
  i            : Integer;
  sconto       : integer;
  scontoTotale : double;

begin
  strArray := System.StrUtils.SplitString(formula, '+');

  scontoTotale := 1;

  for i := 0 to Length(strArray)-1 do begin
    sconto       := strToIntDef(strArray[i], 0);
    scontoTotale := scontoTotale * ( 1-sconto/100);
  end;

  result := scontoTotale;
end;


// ********************************************************
//
// CREAZIONE XML
//
// ********************************************************


function feGeneraFatturaElettronica(xmlFileName : string; owner : TForm; idDocumento : integer) : boolean;

var
  XMLDoc    : IXMLDocument;

var
  // nodi
  iNodoLiv0             : IXMLNode;

begin
  // ...
  feInitializeDBConnection;
  feQuerySetup(idDocumento);

  // ======================================
  // Crea XML
  // ======================================


  try
    // ...
    XMLDoc := NewXMLDocument;

    // codifica utf
    XMLDoc.Encoding := 'utf-8';
    // options
    XMLDoc.Options  := [doNodeAutoIndent]; // looks better in Editor ;)


    // ======================================
    // <p:FatturaElettronica>
    // ======================================

    // doc
    // https://stackoverflow.com/questions/48172801/delphi-berlin-10-1-ixmldocument-root-node-prefix
    // ok

    iNodoLiv0 := XMLDoc.AddChild('p:FatturaElettronica', 'http://ivaservizi.agenziaentrate.gov.it/docs/xsd/fatture/v1.2');
    iNodoLiv0.Attributes['versione']:='FPA12';
    iNodoLiv0.DeclareNamespace('ds','http://www.w3.org/2000/09/xmldsig#');
    iNodoLiv0.DeclareNamespace('p','http://ivaservizi.agenziaentrate.gov.it/docs/xsd/fatture/v1.2');
    iNodoLiv0.DeclareNamespace('xsi','http://www.w3.org/2001/XMLSchema-instance');

    // ======================================
    // HEADER
    // ======================================

    // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018.PDF
    // header 2.1 parte prima - PG 29
    //
    // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

    // 1.1 ... 1.6
    feAddFatturaElettronicaHeader(XMLDoc, iNodoLiv0);

    // ======================================
    // BODY
    // ======================================

    // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018.PDF
    // header 2.1 parte prima - PG 29
    //
    // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls
    // 1.1 ... 1.6
    feAddFatturaElettronicaBody(XMLDoc, iNodoLiv0);

    // ======================================
    //
    // ======================================

//  iRoot := XMLDoc.AddChild('xml');
//  iNode := iRoot.AddChild('test');
//  iNode.AddChild('test2');
//  iChild := iNode.AddChild('test3');
//  iChild.Text := 'Simple value';
//  iNode.AddChild('test4', iNode.ChildNodes.IndexOf(iChild));
//  iNode2 := iNode.CloneNode(True);
//  iRoot.ChildNodes.Add(iNode2);
//  iNode2.Attributes['color'] := 'red';

    // ======================================
    //
    // ======================================

    XMLDoc.saveToFile(xmlFileName);
    XMLDoc.active := False;

    // ======================================
    //
    // ======================================

    qryDatiImpresa   .close;
    qryDocumento     .close;
    qryDocumentoRighe.close;
  finally
    //XMLDoc.Free;
  end;
end;

// ********************************************************
//
//
// FATTURA ELETTRONICA : HEADER
//
//
// ********************************************************

function feAddFatturaElettronicaHeader_DatiTrasmissione(const iNodoLiv1: IXMLNode) : boolean;

var
  // nodi
  iNodoLiv2 : IXMLNode;
  iNodoLiv3 : IXMLNode;
  iNodoLiv4 : IXMLNode;
  iNodoLiv5 : IXMLNode;

  tmp       : string;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // PG 29 - 30

  // TRACCIATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // 1.1   <DatiTrasmissione>
  iNodoLiv2               := iNodoLiv1.addChild('DatiTrasmissione');

  // ======================================
  // 1.1 <DatiTrasmissione>
  // 1.1.1   <IdTrasmittente>
  // ======================================

  // 1.1.1   <IdTrasmittente>
  iNodoLiv3               := iNodoLiv2.addChild('IdTrasmittente');
  // 1.1.1.1   <IdPaese>
  iNodoLiv4               := iNodoLiv3.addChild('IdPaese');
  tmp                     := qryDatiImpresa.fieldByName('IdPaese').asString;    // partita iva dell'azienda
  iNodoLiv4.text          := tmp;                                               // noi inviamo dall'Italia
  // 1.1.1.2   <IdCodice>
  iNodoLiv4               := iNodoLiv3.addChild('IdCodice');
  tmp                     := qryDatiImpresa.fieldByName('PartitaIva').asString; // partita iva dell'azienda
  iNodoLiv4.Text          := tmp;

  // ======================================
  // 1.1 <DatiTrasmissione>
  // 1.1.2   <ProgressivoInvio>
  // 1.1.3   <FormatoTrasmissione>
  // 1.1.4   <CodiceDestinatario>
  // ======================================

  // 1.1.2   <ProgressivoInvio>
  iNodoLiv3               := iNodoLiv2.addChild('ProgressivoInvio');
  dateTimeToString(tmp, 'yyyymmdd_hh:nn:ss', now);
  iNodoLiv3.Text          := tmp;

  //1.1.3   <FormatoTrasmissione>
  iNodoLiv3               := iNodoLiv2.addChild('FormatoTrasmissione');
  iNodoLiv3.Text          := 'FPR12'; // invio fra privati

  //1.1.4   <CodiceDestinatario>
  iNodoLiv3               := iNodoLiv2.addChild('CodiceDestinatario');
  iNodoLiv3.Text          := '0000000'; // uso la PEC del destinatario

  // ======================================
  // 1.1 <DatiTrasmissione>
  // 1.1.5   <ContattiTrasmittente>
  // ======================================

  // 1.1.5   <ContattiTrasmittente>
  iNodoLiv3               := iNodoLiv2.addChild('ContattiTrasmittente');
  // 1.1.5.1   <Telefono>
  iNodoLiv4               := iNodoLiv3.addChild('Telefono');
  tmp                     := qryDatiImpresa.fieldByName('Telefono').asString;
  iNodoLiv4.text          := tmp;
  // 1.1.5.2   <Email>
  iNodoLiv4               := iNodoLiv3.addChild('Email');
  tmp                     := qryDatiImpresa.fieldByName('Email').asString;
  iNodoLiv4.text          := tmp;

  // ======================================
  // 1.1 <DatiTrasmissione>
  // 1.1.6   <PECDestinatario>
  // ======================================

  // 1.1.6   <PECDestinatario>
  iNodoLiv3               := iNodoLiv2.addChild('PECDestinatario');
  tmp                     := qryAnagrafica.fieldByName('PecAziendale').asString;
  iNodoLiv3.text          := tmp;
end;

function feAddFatturaElettronicaHeader_CedentePrestatore(const iNodoLiv1: IXMLNode) : boolean;

var
  // nodi
  iNodoLiv2 : IXMLNode;
  iNodoLiv3 : IXMLNode;
  iNodoLiv4 : IXMLNode;
  iNodoLiv5 : IXMLNode;

  tmp       : string;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // PG 30 - 30

  // TRACCIATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // 1.2   <CedentePrestatore>
  iNodoLiv2               := iNodoLiv1.addChild('CedentePrestatore');

  // ======================================
  // 1.2  <CedentePrestatore>
  // 1.2.1  <DatiAnagrafici>
  // ======================================

  // 1.2.1<DatiAnagrafici>
  iNodoLiv3               := iNodoLiv2.addChild('DatiAnagrafici');

  // 1.2.1.1   <IdFiscaleIVA>
  iNodoLiv4               := iNodoLiv3.addChild('IdFiscaleIVA');
  // 1.2.1.1.1   <IdPaese>
  iNodoLiv5               := iNodoLiv4.addChild('IdPaese');
  tmp                     := qryDatiImpresa.fieldByName('IdPaese').asString;    // IT
  iNodoLiv5.text          := tmp;
  // 1.2.1.1.2   <IdCodice>
  iNodoLiv5               := iNodoLiv4.addChild('IdCodice');
  tmp                     := qryDatiImpresa.fieldByName('PartitaIva').asString; // partita iva dell'azienda
  iNodoLiv5.text          := tmp;

  // 1.2.1.2   <CodiceFiscale>
  iNodoLiv4               := iNodoLiv3.addChild('CodiceFiscale');
  tmp                     := qryDatiImpresa.fieldByName('PartitaIva').asString; // partita iva dell'azienda
  iNodoLiv4.text          := tmp;

  // 1.2.1.3   <Anagrafica>
  iNodoLiv4               := iNodoLiv3.addChild('Anagrafica');
  // 1.2.1.3.1   <Denominazione>
  iNodoLiv5               := iNodoLiv4.addChild('Denominazione');
  tmp                     := qryDatiImpresa.fieldByName('Denominazione').asString;
  iNodoLiv5.text          := tmp;

  // 1.2.1.3.2   <Nome>
  // 1.2.1.3.3   <Cognome>
  // 1.2.1.3.4   <Titolo>
  // 1.2.1.3.5   <CodEORI>

  // 1.2.1.8   <RegimeFiscale>
  iNodoLiv4               := iNodoLiv3.addChild('RegimeFiscale');
  tmp                     := qryDatiImpresa.fieldByName('RegimeFiscale').asString;
  iNodoLiv4.text          := tmp;

  // ======================================
  // 1.2  <CedentePrestatore>
  // 1.2.2   <Sede>
  // ======================================

  // 1.2.2   <Sede>
  iNodoLiv3               := iNodoLiv2.addChild('Sede');

  // 1.2.2.1   <Indirizzo>
  iNodoLiv4               := iNodoLiv3.addChild('Indirizzo');
  tmp                     := qryDatiImpresa.fieldByName('Indirizzo').asString;
  iNodoLiv4.text          := tmp;

  // 1.2.2.2   <NumeroCivico>
  iNodoLiv4               := iNodoLiv3.addChild('NumeroCivico');
  tmp                     := qryDatiImpresa.fieldByName('NumeroCivico').asString;
  iNodoLiv4.text          := tmp;

  // 1.2.2.3   <CAP>
  iNodoLiv4               := iNodoLiv3.addChild('CAP');
  tmp                     := qryDatiImpresa.fieldByName('CAP').asString;
  iNodoLiv4.text          := tmp;

  // 1.2.2.4   <Comune>
  iNodoLiv4               := iNodoLiv3.addChild('Comune');
  tmp                     := qryDatiImpresa.fieldByName('Comune').asString;
  iNodoLiv4.text          := tmp;

  // 1.2.2.5   <Provincia>
  iNodoLiv4               := iNodoLiv3.addChild('Provincia');
  tmp                     := qryDatiImpresa.fieldByName('Provincia').asString;
  iNodoLiv4.text          := tmp;

  // 1.2.2.6   <Nazione>
  iNodoLiv4               := iNodoLiv3.addChild('Nazione');
  tmp                     := qryDatiImpresa.fieldByName('Nazione').asString;
  iNodoLiv4.text          := tmp;

  // ======================================
  // 1.2  <CedentePrestatore>
  // 1.2.4   <IscrizioneREA>
  // ======================================

  // 1.2.4   <IscrizioneREA>
  iNodoLiv3               := iNodoLiv2.addChild('IscrizioneREA');
end;


function feAddFatturaElettronicaHeader_CessionarioCommittente(const iNodoLiv1: IXMLNode) : boolean;

var
  // nodi
  iNodoLiv2 : IXMLNode;
  iNodoLiv3 : IXMLNode;
  iNodoLiv4 : IXMLNode;
  iNodoLiv5 : IXMLNode;

  tmp       : string;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // PG 30 - 30

  // TRACCIATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // 1.4   <CessionarioCommittente>
  iNodoLiv2               := iNodoLiv1.addChild('CessionarioCommittente');

  // ======================================
  // 1.4   <CessionarioCommittente>						Blocco sempre obbligatorio contenente dati relativi al cessionario / committente (cliente)
  // 1.4.1   <DatiAnagrafici>							Blocco contenente i dati fiscali e anagrafici del cessionario/committente
  // ======================================

  // 1.4.1   <DatiAnagrafici>
  iNodoLiv3               := iNodoLiv2.addChild('DatiAnagrafici');

  // 1.4.1.1   <IdFiscaleIVA>
  iNodoLiv4               := iNodoLiv3.addChild('IdFiscaleIVA');
  // 1.4.1.1.1   <IdPaese>
  iNodoLiv5               := iNodoLiv4.addChild('IdPaese');
  tmp                     := qryDocumento.fieldByName('Anagr_IdPaese').asString;    // IT
  iNodoLiv5.text          := tmp;
  // 1.4.1.1.2   <IdCodice>
  iNodoLiv5               := iNodoLiv4.addChild('IdCodice');
  tmp                     := qryDocumento.fieldByName('Anagr_PartitaIva').asString; // partita iva dell'azienda
  iNodoLiv5.text          := tmp;

  // 1.4.1.2   <CodiceFiscale>
  iNodoLiv4               := iNodoLiv3.addChild('CodiceFiscale');
  tmp                     := qryDocumento.fieldByName('Anagr_CodiceFiscale').asString; // partita iva dell'azienda
  iNodoLiv4.text          := tmp;

  // 1.4.1.3   <Anagrafica>
  iNodoLiv4               := iNodoLiv3.addChild('Anagrafica');
  // 1.4.1.3.1   <Denominazione>
  iNodoLiv5               := iNodoLiv4.addChild('Denominazione');
  tmp                     := qryDocumento.fieldByName('Anagr_Nome').asString;
  iNodoLiv5.text          := tmp;

  //1.4.1.3.2   <Nome>				xs:normalizedString	Nome della persona fisica. Da valorizzare insieme all'elemento informativo 1.4.1.3.3  <Cognome> ed in alternativa all'elemento informativo 1.4.1.3.1 <Denominazione>
  //1.4.1.3.3   <Cognome>				xs:normalizedString	Cognome della persona fisica. Da valorizzare insieme all'elemento informativo 1.4.1.3.2 <Nome> ed in alternativa all'elemento informativo 1.4.1.3.1 <Denominazione>
  //1.4.1.3.4   <Titolo>				xs:normalizedString	Titolo onorifico
  //1.4.1.3.5   <CodEORI>				xs:string	Numero del Codice EORI (Economic Operator Registration and Identification)  in base al Regolamento (CE) n. 312 del 16 aprile 2009. In vigore dal 1 luglio 2009

  // ======================================
  // 1.4   <CessionarioCommittente>
  // 1.4.2   <Sede>
  // ======================================

  // 1.4.2   <Sede>
  iNodoLiv3               := iNodoLiv2.addChild('Sede');

  // 1.4.2.1   <Indirizzo>
  iNodoLiv4               := iNodoLiv3.addChild('Indirizzo');
  tmp                     := qryDocumento.fieldByName('Anagr_Indirizzo').asString;
  iNodoLiv4.text          := tmp;

  // 1.4.2.2   <NumeroCivico>
  //iNodoLiv4               := iNodoLiv3.addChild('NumeroCivico');
  //tmp                     := qryDocumento.fieldByName('NumeroCivico').asString;
  //iNodoLiv4.text          := tmp;

  // 1.4.2.3   <CAP>
  iNodoLiv4               := iNodoLiv3.addChild('CAP');
  tmp                     := qryDocumento.fieldByName('Anagr_Cap').asString;
  iNodoLiv4.text          := tmp;

  // 1.4.2.4   <Comune>
  iNodoLiv4               := iNodoLiv3.addChild('Comune');
  tmp                     := qryDocumento.fieldByName('Anagr_Citta').asString;
  iNodoLiv4.text          := tmp;

  // 1.4.2.5   <Provincia>
  iNodoLiv4               := iNodoLiv3.addChild('Provincia');
  tmp                     := qryDocumento.fieldByName('Anagr_Prov').asString;
  iNodoLiv4.text          := tmp;

  // 1.4.2.6   <Nazione>
  iNodoLiv4               := iNodoLiv3.addChild('Nazione');
  tmp                     := qryDocumento.fieldByName('Anagr_IdPaese').asString;
  iNodoLiv4.text          := tmp;
end;


// https://stackoverflow.com/questions/8354658/how-to-create-xml-file-in-delphi

function feAddFatturaElettronicaHeader(const XMLDoc: IXMLDocument; const iNodoLiv0 : IXMLNode) : boolean;

var
  // nodi
  iNodoLiv1             : IXMLNode;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // TRACCIATO SEMPLIFICATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // ======================================
  // 1 <FatturaElettronicaHeader>
  // ======================================

  //iNodoLiv1               := iNodoLiv0.addChild('FatturaElettronicaHeader');
  iNodoLiv1               := XMLDoc.CreateElement('FatturaElettronicaHeader', '');
  iNodoLiv0.ChildNodes.Add(iNodoLiv1);

  // 1.1   <DatiTrasmissione>
  feAddFatturaElettronicaHeader_DatiTrasmissione (iNodoLiv1);
  // 1.2   <CedentePrestatore>
  feAddFatturaElettronicaHeader_CedentePrestatore(iNodoLiv1);
  // 1.3   <RappresentanteFiscale>
  // 1.4   <CessionarioCommittente>
  feAddFatturaElettronicaHeader_CessionarioCommittente(iNodoLiv1);
  // 1.5   <TerzoIntermediarioOSoggettoEmittente>
  // 1.6   <SoggettoEmittente>
end;

// ********************************************************
//
// FATTURA ELETTRONICA : Body
//
// ********************************************************

function feAddFatturaElettronicaBody_DatiGenerali(const iNodoLiv1: IXMLNode) : boolean;

var
  // nodi
  iNodoLiv2 : IXMLNode;
  iNodoLiv3 : IXMLNode;
  iNodoLiv4 : IXMLNode;
  iNodoLiv5 : IXMLNode;

  tmp             : string;
  importoRitenuta : currency;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // PG 39 - 30

  // TRACCIATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // 2.1   <DatiGenerali>
  iNodoLiv2               := iNodoLiv1.addChild('DatiGenerali');

  // ======================================
  // 2.1   <DatiGenerali>
  // 2.1.1   <DatiGeneraliDocumento>
  // ======================================

  // 2.1.1   <DatiGeneraliDocumento>
  iNodoLiv3               := iNodoLiv2.addChild('DatiGeneraliDocumento');
  // 2.1.1.1   <TipoDocumento>
  //  TD01		fattura
  //  TD02		acconto/anticipo su fattura
  //  TD03		acconto/anticipo su parcella
  //  TD04		nota di credito
  //  TD05		nota di debito
  //  TD06		parcella
  //  TD20		autofattura
  iNodoLiv4               := iNodoLiv3.addChild('TipoDocumento');
  tmp                     := qryTipoDocumento.fieldByName('FatturaElettronicaTipoDocumento').asString;
  assert(tmp <> '');
  iNodoLiv4.text          := tmp;
  // 2.1.1.2   <Divisa>
  iNodoLiv4               := iNodoLiv3.addChild('Divisa');
  tmp                     := 'EUR'; // attualmente prevediamo solo euro
  iNodoLiv4.Text          := tmp;

  // 2.1.1.3   <Data>
  // formato ISO 8601:2004, con la  precisione seguente:   YYYY-MM-DD
  iNodoLiv4               := iNodoLiv3.addChild('Data');
  tmp                     := formatdatetime('YYYY-MM-DD', qryDocumento.fieldByName('Data').asDateTime);
  iNodoLiv4.text          := tmp;

  // 2.1.1.4   <Numero>
  iNodoLiv4               := iNodoLiv3.addChild('Numero');
  tmp                     := qryDocumento.fieldByName('Numero').asString;
  iNodoLiv4.text          := tmp;

  // ======================================
  // 2.1   <DatiGenerali>
  // 2.1.1   <DatiGeneraliDocumento>
  // 2.1.1.5   <DatiRitenuta>
  // ======================================

  // importo ritenuta
  importoRitenuta         := qryDocumento.fieldByName('TotRitAcconto').asCurrency;

  // controlla che vada valorizzato
  if importoRitenuta <> 0.0 then begin
    // 2.1.1.5   <DatiRitenuta>
    iNodoLiv4               := iNodoLiv3.addChild('DatiRitenuta');

    // 2.1.1.5.1   <TipoRitenuta>				        xs:string	Tipologia della ritenuta	"valori ammessi: [RT01]: ritenuta pers. fisiche [RT02]: ritenuta pers. giurid."	<1.1>	4
    iNodoLiv5               := iNodoLiv3.addChild('TipoRitenuta');
    tmp                     := qryTipoDocumento.fieldByName('FatturaElettronicaTipoRitenuta').asString;
    iNodoLiv5.text          := tmp;

    // 2.1.1.5.2   <ImportoRitenuta>				xs:decimal	Importo della ritenuta	formato numerico; i decimali vanno separati dall'intero con il carattere  '.' (punto)	<1.1>
    iNodoLiv5               := iNodoLiv3.addChild('ImportoRitenuta');
    importoRitenuta         := qryDocumento.fieldByName('TotRitAcconto').asCurrency;
    tmp                     := floattostrf(importoRitenuta, ffFixed, 4, 2);
    iNodoLiv5.text          := tmp;

    // 2.1.1.5.3   <AliquotaRitenuta>				xs:decimal	Aliquota (%) della ritenuta	formato numerico; i decimali vanno separati dall'intero con il carattere  '.' (punto)	<1.1>	4 … 6
    iNodoLiv5               := iNodoLiv3.addChild('AliquotaRitenuta');
    tmp                     := qryTipoDocumento.fieldByName('FatturaElettronicaAliquotaRitenuta').asString;
    assert(tmp<>'');
    iNodoLiv5.text          := tmp;

    // 2.1.1.5.4   <CausalePagamento>				xs:string	Causale del pagamento (quella del modello 770)	"valori ammessi:codifiche come da Mod. 770S"	<1.1>	1 … 2
    // A, B, C ...
    // A = Prestazioni di lavoro autonomo rientranti nell’esercizio di arte o professione abituale.
    // D = Utili spettanti ai soci promotori e ai soci fondatori delle società di capitali.
    // E = Levata di protesti cambiari da parte dei segretari comunali.
    // G = Indennità corrisposte per la cessazione di attività sportiva professionale.
    // vedi sito : https://www.fatturapertutti.it/supporto/soggetti-a-ritenuta-causali-di-pagamento-come-da-istruzioni-modello-770s-874
    iNodoLiv5               := iNodoLiv3.addChild('CausalePagamento');
    tmp                     := qryTipoDocumento.fieldByName('FatturaElettronicaCausalePagamentoMod770').asString;
    assert(tmp<>'');
    iNodoLiv5.text          := tmp;
  end;

  // ======================================
  // 2.1.1.6   <DatiBollo>
  // 2.1.1.6.1   <BolloVirtuale>
  // 2.1.1.6.2   <ImportoBollo>
  // ======================================

  // 2.1.1.6   <DatiBollo>
  // 2.1.1.6.1   <BolloVirtuale>				xs:string	Bollo assolto ai sensi del decreto MEF 17 giugno 2014 (art. 6)
  // 2.1.1.6.2   <ImportoBollo>				        xs:decimal	Importo del bollo

  // 2.1.1.8   <ScontoMaggiorazione>
  // 2.1.1.8.1   <Tipo>
  // 2.1.1.8.2   <Percentuale>
  // 2.1.1.8.3   <Importo>

  // 2.1.1.9   <ImportoTotaleDocumento>
  // 2.1.1.10   <Arrotondamento>
  // 2.1.1.11   <Causale>
  // 2.1.1.12   <Art73>

  // 2.1.2   <DatiOrdineAcquisto>
  // 2.1.2.1   <RiferimentoNumeroLinea>
  // 2.1.2.2   <IdDocumento>
  // 2.1.2.3   <Data>
  // 2.1.2.4   <NumItem>
  // 2.1.2.5   <CodiceCommessaConvenzione>
  // 2.1.2.6   <CodiceCUP>
  // 2.1.2.7   <CodiceCIG>

  // 2.1.6   <DatiFattureCollegate>

  // 2.1.8   <DatiDDT>							Blocco da valorizzare nei casi di fattura "differita" per indicare il documento con cui è stato consegnato il bene (gli elementi informativi del blocco possono essere ripetuti se la fattura fa riferimento a più consegne e quindi a più documenti di trasporto)
  // 2.1.8.1   <NumeroDDT>					xs:normalizedString	Numero del documento di trasporto
  // 2.1.8.2   <DataDDT>					xs:date	Data del documento di trasporto (secondo il formato ISO 8601:2004)
  // 2.1.8.3   <RiferimentoNumeroLinea>					xs:integer	Linea di dettaglio della fattura cui si riferisce il DDT  (non viene valorizzato  se il riferimento è all'intera fattura) (vedi elemento informativo 2.2.1.1 <NumeroLinea>)

  // ...
//  qryDocumentoRighe.first;
//  cnt := 0;
//
//  // per tutte le righe
//  while not qryDocumentoRighe.eof do begin
//
//!    // ...
//    qryDocumentoRighe.Next;
//  end;
//

  // ======================================
  // 1.1 <DatiTrasmissione>
  // 1.1.2   <ProgressivoInvio>
  // 1.1.3   <FormatoTrasmissione>
  // 1.1.4   <CodiceDestinatario>
  // ======================================

//  // 1.1.2   <ProgressivoInvio>
//  iNodoLiv3               := iNodoLiv2.addChild('ProgressivoInvio');
//  dateTimeToString(tmp, 'yyyymmdd_hh:nn:ss', now);
//  iNodoLiv3.Text          := tmp;
//
//  //1.1.3   <FormatoTrasmissione>
//  iNodoLiv3               := iNodoLiv2.addChild('FormatoTrasmissione');
//  iNodoLiv3.Text          := 'FPR12'; // invio fra privati
//
//  //1.1.4   <CodiceDestinatario>
//  iNodoLiv3               := iNodoLiv2.addChild('CodiceDestinatario');
//  iNodoLiv3.Text          := '0000000'; // uso la PEC del destinatario
end;

function feAddFatturaElettronicaBody_DatiBeniServizi(const iNodoLiv1: IXMLNode) : boolean;

var
  // nodi
  iNodoLiv2 : IXMLNode;
  iNodoLiv3 : IXMLNode;
  iNodoLiv4 : IXMLNode;
  iNodoLiv5 : IXMLNode;
  iNodoLiv5Tipo : IXMLNode;

  tmp       : string;
  tmpc      : currency;
  tmpd      : double;

  cnt       : integer;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // PG 47 - 52

  // TRACCIATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // 2.2   <DatiBeniServizi>
  iNodoLiv2               := iNodoLiv1.addChild('DatiBeniServizi');

  // ======================================
  // 2.2   <DatiBeniServizi>
  // 2.2.1   <DettaglioLinee>
  // ======================================

  // ...
  qryDocumentoRighe.first;
  cnt := 0;

  // per tutte le righe
  while not qryDocumentoRighe.eof do begin
    if (qryDocumentoRighe     .fieldByName('CodArticolo').asString = '')  and
       (qryDocumentoRighe     .fieldByName('Quantita')   .asFloat = 0.0 ) and
       (trim(qryDocumentoRighe.fieldByName('Descrizione').asString) = '') and
       ((qryDocumentoRighe    .fieldByName('PrezzoNetto').IsNull) or
       (qryDocumentoRighe     .fieldByName('PrezzoNetto').AsCurrency = 0.0)) then begin

       // ...
       qryDocumentoRighe.Next;

       // ...
       continue;
    end;

    // ...
    inc(cnt);

    // 2.2.1   <DettaglioLinee>
    iNodoLiv3               := iNodoLiv2.addChild('DettaglioLinee');

    // 2.2.1.1   <NumeroLinea>
    iNodoLiv4               := iNodoLiv3.addChild('NumeroLinea');
    tmp                     := intToStr(cnt);
    iNodoLiv4.text          := tmp;

    // 2.2.1.2   <TipoCessionePrestazione>
    //"valori ammessi:
    //
    //[SC]: sconto
    //7[PR]: premio
    //[AB]: abbuono
    //[AC]: spesa accessoria"
    //
    //iNodoLiv4               := iNodoLiv3.addChild('TipoCessionePrestazione');
    //tmp                     := qryDocumentoRighe.fieldByName('NONAME').asString; // partita iva dell'azienda
    //iNodoLiv4.Text          := tmp;

    // ======================================
    // 2.2.1.3   <CodiceArticolo>
    // ======================================

    if qryDocumentoRighe.fieldByName('CodArticolo').asString <> '' then begin
      // 2.2.1.3   <CodiceArticolo>
      iNodoLiv4               := iNodoLiv3.addChild('CodiceArticolo');
      // 2.2.1.3.1   <CodiceTipo>
      iNodoLiv5               := iNodoLiv4.addChild('CodiceTipo');
      tmp                     := 'INT.AZ';
      iNodoLiv5.text          := tmp;
      // 2.2.1.3.2   <CodiceValore>
      iNodoLiv5               := iNodoLiv4.addChild('CodiceValore');
      tmp                     := qryDocumentoRighe.fieldByName('CodArticolo').asString;
      iNodoLiv5.text          := tmp;
    end;

    // 2.2.1.4   <Descrizione>
    iNodoLiv4               := iNodoLiv3.addChild('Descrizione');
    tmp                     := qryDocumentoRighe.fieldByName('Descrizione').asString;
    iNodoLiv4.text          := tmp;

    // ======================================
    // 2.2.1.5   <Quantita>
    // ======================================

    // 2.2.1.5   <Quantita>
    iNodoLiv4               := iNodoLiv3.addChild('Quantita');
    tmp                     := qryDocumentoRighe.fieldByName('Quantita').asString;
    iNodoLiv4.text          := tmp;

    // 2.2.1.6   <UnitaMisura>
    iNodoLiv4               := iNodoLiv3.addChild('UnitaMisura');
    tmp                     := qryDocumentoRighe.fieldByName('Udm').asString;
    iNodoLiv4.text          := tmp;

    // ======================================
    // 2.2.1.7 + 2.2.1.8  <PERIODO>
    // ======================================

    // ...
    if (not qryDocumentoRighe.fieldByName('PeriodoDataInizio').isNull) or
       (not qryDocumentoRighe.fieldByName('PeriodoDataFine')  .isNull) then begin

      // 2.2.1.7   <DataInizioPeriodo>
      iNodoLiv4               := iNodoLiv3.addChild('DataInizioPeriodo');
      tmp                     := qryDocumentoRighe.fieldByName('PeriodoDataInizio').asString;
      iNodoLiv4.text          := tmp;

      // 2.2.1.8   <DataFinePeriodo>
      iNodoLiv4               := iNodoLiv3.addChild('DataFinePeriodo');
      tmp                     := qryDocumentoRighe.fieldByName('PeriodoDataFine').asString;
      iNodoLiv4.text          := tmp;
    end;

    // ======================================
    // 2.2.1.9   <PrezzoUnitario>
    // ======================================

    // 2.2.1.9   <PrezzoUnitario>
    iNodoLiv4               := iNodoLiv3.addChild('PrezzoUnitario');
    tmpc                    := qryDocumentoRighe.fieldByName('PrezzoNetto').asCurrency;
    tmp                     := floattostrf(tmpc, ffFixed, 4, 2);
    tmp                     := stringreplace(tmp, ',', '.', [rfReplaceAll, rfIgnoreCase]);
    iNodoLiv4.text          := tmp;

    // ======================================
    // 2.2.1.10   <ScontoMaggiorazione>
    // ======================================

    if (not qryDocumentoRighe.fieldByName('Sconti').IsNull) and
       (qryDocumentoRighe.fieldByName('Sconti').asString <> '') then begin
      // 2.2.1.10   <ScontoMaggiorazione>
      iNodoLiv4               := iNodoLiv3.addChild('ScontoMaggiorazione');

      // 2.2.1.10.1   <Tipo>
      iNodoLiv5Tipo           := iNodoLiv4.addChild('Tipo');

      // 2.2.1.10.2   <Percentuale>
      iNodoLiv5               := iNodoLiv4.addChild('Percentuale');
      // ...
      tmpd                    := 1-calcolaScontoDaFormula(qryDocumentoRighe.fieldByName('Sconti').asString);
      tmpd                    := tmpd * 100;

      // 2.2.1.10.1   <Tipo>
      if tmpd > 0 then begin
        // tipo
        tmp                     := 'SC';
        iNodoLiv5Tipo.text      := tmp;
      end else begin
        // tipo
        tmp                     := 'MG';
        iNodoLiv5Tipo.text      := tmp;
        tmpd                    := - tmpd;
      end;

      // percentuale
      tmp                     := floattostrf(tmpd, ffNumber, 4, 2);
      tmp                     := stringreplace(tmp, ',', '.', [rfReplaceAll, rfIgnoreCase]);
      iNodoLiv5.text          := tmp;

      // 2.2.1.10.3   <Importo>
      iNodoLiv5               := iNodoLiv4.addChild('Importo');
      tmpc                    := qryDocumentoRighe.fieldByName('PrezzoNetto').asCurrency;
      tmpc                    := tmpc * tmpd / 100;
      tmp                     := floattostrf(tmpc, ffFixed, 4, 2);
      tmp                     := stringreplace(tmp, ',', '.', [rfReplaceAll, rfIgnoreCase]);
      iNodoLiv5.text          := tmp;
    end;

    // ======================================
    // 2.2.1.11   <PrezzoTotale>
    // ======================================

    // 2.2.1.11   <PrezzoTotale>
    iNodoLiv4               := iNodoLiv3.addChild('PrezzoTotale');
    tmpc                    := qryDocumentoRighe.fieldByName('ImportoNettoRiga').asCurrency;
    tmp                     := floattostrf(tmpc, ffFixed, 4, 2);
    tmp                     := stringreplace(tmp, ',', '.', [rfReplaceAll, rfIgnoreCase]);
    iNodoLiv4.text          := tmp;

    // 2.2.1.12   <AliquotaIVA>
    iNodoLiv4               := iNodoLiv3.addChild('AliquotaIVA');
    tmpd                    := qryDocumentoRighe.fieldByName('PercIva').asFloat;
    tmp                     := floattostrf(tmpd, ffFixed, 4, 2);
    tmp                     := stringreplace(tmp, ',', '.', [rfReplaceAll, rfIgnoreCase]);
    iNodoLiv4.text          := tmp;

    // ======================================
    // 2.2.1.13   <Ritenuta>
    // ======================================

    // 2.2.1.13   <Ritenuta>
    if qryDocumentoRighe.fieldByName('RitAcconto').asBoolean then begin
      // 2.2.1.13   <Ritenuta>
      iNodoLiv4               := iNodoLiv3.addChild('Ritenuta');
      tmp                     := 'SI';
      iNodoLiv4.text          := tmp;
    end;

    // ======================================
    // 2.2.1.14   <Natura>
    // ======================================

    tmpd                    := qryDocumentoRighe.fieldByName('PercIva').asFloat;

    // se iva indicata è 0.0 indicare la "natura" della motiviazione
    if tmpd = 0.0 then begin
      // 2.2.1.14   <Natura>
      iNodoLiv4               := iNodoLiv3.addChild('Natura');
      tmp                     := qryDocumentoRighe.fieldByName('Natura').asString;
      iNodoLiv4.text          := tmp;
    end;

    // 2.2.1.15   <RiferimentoAmministrazione>

    // ======================================
    // 2.2.1.16   <AltriDatiGestionali>
    // ======================================

    // 2.2.1.16   <AltriDatiGestionali>
    // 2.2.1.16.1   <TipoDato>
    // 2.2.1.16.2   <RiferimentoTesto>
    // 2.2.1.16.3   <RiferimentoNumero>
    // 2.2.1.16.4   <RiferimentoData>

    // ...
    qryDocumentoRighe.Next;
  end;

end;

// https://stackoverflow.com/questions/8354658/how-to-create-xml-file-in-delphi

function feAddFatturaElettronicaBody  (const XMLDoc: IXMLDocument; const iNodoLiv0 : IXMLNode) : boolean;

var
  iNodoLiv1 : IXMLNode;

begin
  // Allegato+A+-+Specifiche+tecniche+vers+1.1_22062018
  // TRACCIATO SEMPLIFICATO
  // Rappresentazione+tabellare+del+tracciato+fattura+ordinaria.xls

  // ======================================
  // 2   <FatturaElettronicaBody>
  // ======================================

  // 2
 // iNodoLiv1 := iNodoLiv0.addChild('FatturaElettronicaBody');

  iNodoLiv1               := XMLDoc.CreateElement('FatturaElettronicaBody', '');
  iNodoLiv0.ChildNodes.Add(iNodoLiv1);


  // 2.1   <DatiGeneraliDocumento>
  feAddFatturaElettronicaBody_DatiGenerali(iNodoLiv1);

  // 2.2   <DatiBeniServizi>
  feAddFatturaElettronicaBody_DatiBeniServizi(iNodoLiv1);
end;

// ********************************************************
//
//
//
// ********************************************************

initialization begin
  try
    qryDatiImpresa    := nil;
    qryDocumento      := nil;
    qryDocumentoRighe := nil;
    qryTipoDocumento  := nil;
    qryAnagrafica     := nil;
  except
  end;
end;

finalization begin
  feFinalizeDBConnection;
end;

end.
