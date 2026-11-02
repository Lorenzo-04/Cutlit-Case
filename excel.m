clear; clc;

%%\ ---------------- IMPOSTAZIONI ----------------
mdl = 'ProgettoIT_2_3_1d'              % numero di repliche (es. 5 per il report) %[output:0d623131]
fileOut ='risultati_Cutlit_2_3_1d.xlsx';   % file Excel di output
nRep = 5;
% Saturazioni dell'analisi a valori medi (Excel punto 1)
satExcel = struct('Printing',0.818, 'Punch',0.895, 'Linear',0.122, ...
                  'Window',0.546, 'Folding',0.761, 'Folder',0.978, 'Showcard',0.269);
prodotti = {'P001';'P002';'P003';'P004';'P005';'P006';'P007'};
target   = [90; 90; 90; 435; 165; 135; 360];   % tempo max di attraversamento [h]
costoRit = 20;                                  % €/h per ordine in ritardo

%%\ ---------------- COPIA TEMPORANEA DEL MODELLO ----------------
src = fullfile(pwd, [mdl '.slx']);
if ~isfile(src)
    error('Non trovo %s: mettete lo script nella cartella del modello e controllate il nome in "mdl".', src);
end
tmpMdl = 'tmp_cutlit_run';
if bdIsLoaded(tmpMdl), close_system(tmpMdl, 0); end
copyfile(src, fullfile(pwd, [tmpMdl '.slx']), 'f');
load_system(tmpMdl);
Tstop = str2double(get_param(tmpMdl, 'StopTime'));

%%\ ---------------- COLLEGAMENTO DEI LOGGER ----------------
% Server: utilizzo (la porta "util" e' l'ultima statistica, prima dell'uscita entita')
servers = find_system(tmpMdl, 'SearchDepth', 1, 'BlockType', 'EntityServer');
nS = numel(servers);
srvNome = cell(nS,1); srvCap = zeros(nS,1); srvVar = cell(nS,1);
for k = 1:nS
    srvNome{k} = pulisci(get_param(servers{k}, 'Name'));
    srvCap(k)  = str2double(get_param(servers{k}, 'Capacity'));
    if ~strcmp(get_param(servers{k}, 'Utilization'), 'on')
        error('Nel server "%s" la statistica Utilization non e'' attiva.', srvNome{k});
    end
    ph = get_param(servers{k}, 'PortHandles');
    srvVar{k} = sprintf('logU_%d', k);
    aggiungiLogger(tmpMdl, ph.Outport(end-1), srvVar{k});
end

% Generatore: numero di entita' generate (d)
gen = find_system(tmpMdl, 'SearchDepth', 1, 'BlockType', 'EntityGenerator');
haGen = ~isempty(gen) && strcmp(get_param(gen{1}, 'NumberEntitiesDeparted'), 'on');
if haGen
    ph = get_param(gen{1}, 'PortHandles');
    aggiungiLogger(tmpMdl, ph.Outport(1), 'logGen');
end

% Code: numero di entita' in coda (n), solo dove la statistica e' attiva
queues = find_system(tmpMdl, 'SearchDepth', 1, 'BlockType', 'Queue');
qNome = {}; qVar = {}; qSenzaN = {};
for k = 1:numel(queues)
    nm = pulisci(get_param(queues{k}, 'Name'));
    if strcmp(get_param(queues{k}, 'NumberEntitiesInBlock'), 'on')
        idx = 1 + strcmp(get_param(queues{k}, 'NumberEntitiesDeparted'), 'on');
        ph  = get_param(queues{k}, 'PortHandles');
        qNome{end+1,1} = nm;                      %#ok<SAGROW>
        qVar{end+1,1}  = sprintf('logQ_%d', k);   %#ok<SAGROW>
        aggiungiLogger(tmpMdl, ph.Outport(idx), qVar{end});
    else
        qSenzaN{end+1,1} = nm;                    %#ok<SAGROW>
    end
end

%%\ ---------------- SIMULAZIONI ----------------
U      = zeros(nS, nRep);
Qmean  = zeros(numel(qVar), nRep);  Qmax = zeros(numel(qVar), nRep);
riep   = zeros(nRep, 6);   % generati, completati, in ritardo, ritardo tot [h], costo [€], flow medio [h]
ordini = [];               % [replica tipo flowtime ritardo]

rng("shuffle");
for r = 1:nRep %[output:group:9a0111ca]
    fprintf('Replica %d di %d ...\n', r, nRep); %[output:1132ada1]
    rng(r);
    out = sim(tmpMdl, 'ReturnWorkspaceOutputs', 'on');

    for k = 1:nS
        U(k, r) = ultimo(out.get(srvVar{k}));
    end
    for k = 1:numel(qVar)
        [Qmean(k, r), Qmax(k, r)] = mediaTempo(out.get(qVar{k}), Tstop);
    end

    tp = dati(out.get('TYPE'));  ft = dati(out.get('FLOW'));  lt = dati(out.get('LATE'));
    ok = tp >= 1 & tp <= 7;  tp = tp(ok);  ft = ft(ok);  lt = lt(ok);
    ordini = [ordini; repmat(r, numel(tp), 1), tp, ft, lt]; %#ok<AGROW>

    nGen = NaN;  if haGen, nGen = ultimo(out.get('logGen')); end
    riep(r, :) = [nGen, numel(tp), sum(lt > 0), sum(lt), costoRit*sum(lt), mean(ft)];
end %[output:group:9a0111ca]

close_system(tmpMdl, 0);
delete(fullfile(pwd, [tmpMdl '.slx']));

%%\ ---------------- TABELLA 1: SATURAZIONI ----------------
ordineRep = fieldnames(satExcel);
satEx = NaN(nS,1);  pos = zeros(nS,1);
for k = 1:nS
    for j = 1:numel(ordineRep)
        if contains(lower(srvNome{k}), lower(ordineRep{j}))
            satEx(k) = satExcel.(ordineRep{j});  pos(k) = j;  break
        end
    end
end
[~, ord] = sort(pos);
Usim = mean(U, 2);  Usd = std(U, 0, 2);
T1 = table(srvNome(ord), srvCap(ord), satEx(ord), Usim(ord), Usd(ord), Usim(ord) - satEx(ord), ...
    'VariableNames', {'Reparto','Macchine','Saturazione_Excel','Saturazione_Simulazione', ...
                      'Dev_std_repliche','Differenza'});

%%\ ---------------- TABELLA 2: FLOW TIME PER PRODOTTO ----------------
n = zeros(7,1); mFT = NaN(7,1); maxFT = NaN(7,1); qTempo = NaN(7,1); mRit = NaN(7,1);
for p = 1:7
    sel = ordini(:,2) == p;
    n(p) = sum(sel) / nRep;
    if any(sel)
        mFT(p)    = mean(ordini(sel,3));
        maxFT(p)  = max(ordini(sel,3));
        qTempo(p) = mean(ordini(sel,4) == 0);
        mRit(p)   = mean(ordini(sel,4));
    end
end
tot = {'Totale', sum(n), NaN, mean(ordini(:,3)), max(ordini(:,3)), mean(ordini(:,4) == 0), mean(ordini(:,4))};
T2 = table(prodotti, n, target, mFT, maxFT, qTempo, mRit, ...
    'VariableNames', {'Prodotto','Ordini_per_replica','Tempo_max_h','FlowTime_medio_h', ...
                      'FlowTime_max_h','Quota_in_tempo','Ritardo_medio_h'});
T2 = [T2; cell2table(tot, 'VariableNames', T2.Properties.VariableNames)];

%%\ ---------------- TABELLA 3: CODE ----------------
T3 = table(qNome, mean(Qmean, 2), max(Qmax, [], 2), ...
    'VariableNames', {'Coda','Ordini_in_coda_medi','Ordini_in_coda_max'});

%%\ ---------------- TABELLA 4: RIEPILOGO ----------------
voci = {'Modello'; 'Durata simulata [h]'; 'Repliche'; 'Ordini generati'; 'Ordini completati'; ...
        'Ordini in ritardo'; 'Ritardo totale [h]'; 'Costo ritardi [EUR]'; 'Flow time medio [h]'};
media = mean(riep, 1);
valori = {mdl; Tstop; nRep; media(1); media(2); media(3); media(4); media(5); media(6)};
T4 = table(voci, valori, 'VariableNames', {'Voce','Valore_medio'});

T5 = array2table(ordini, 'VariableNames', {'Replica','Prodotto','FlowTime_h','Ritardo_h'});
T6 = array2table([(1:nRep)', riep], 'VariableNames', {'Replica','Generati','Completati', ...
     'In_ritardo','Ritardo_tot_h','Costo_ritardi_EUR','FlowTime_medio_h'});

%%\ ---------------- OUTPUT ----------------
disp('=== SATURAZIONI ===');            disp(T1) %[output:7c1fbff1]
disp('=== FLOW TIME PER PRODOTTO ===');  disp(T2) %[output:695fdea9]
disp('=== CODE ===');                    disp(T3) %[output:76306fdb]
disp('=== RIEPILOGO ===');               disp(T4) %[output:37e47b87]
if ~isempty(qSenzaN) %[output:group:637c1b38]
    fprintf('\nNota: queste code non hanno la statistica "Number of entities in block (n)" attiva\n'); %[output:3957df53]
    fprintf('e non compaiono nella tabella CODE: %s\n', strjoin(qSenzaN', ', ')); %[output:35a4667b]
end %[output:group:637c1b38]
if nRep > 1 && all(Usd < 1e-12) %[output:group:82a5485a]
    fprintf('\nAttenzione: tutte le repliche danno lo stesso risultato (numeri casuali non cambiati).\n'); %[output:556d77b6]
end %[output:group:82a5485a]

if isfile(fileOut), delete(fileOut); end %[output:11c9a96a]
writetable(T4, fileOut, 'Sheet', 'Riepilogo'); %[output:9574d00a]
writetable(T1, fileOut, 'Sheet', 'Saturazioni');
writetable(T2, fileOut, 'Sheet', 'Flow time');
writetable(T3, fileOut, 'Sheet', 'Code');
writetable(T6, fileOut, 'Sheet', 'Repliche');
writetable(T5, fileOut, 'Sheet', 'Ordini');
fprintf('\nRisultati salvati in %s\n', fullfile(pwd, fileOut));

%%\ ================= FUNZIONI DI SUPPORTO =================
function aggiungiLogger(m, srcPort, varName)
    blk = [m '/tmpTW_' varName];
    add_block('simulink/Sinks/To Workspace', blk, 'VariableName', varName, ...
        'SaveFormat', 'Timeseries', 'MaxDataPoints', 'inf');
    dst = get_param(blk, 'PortHandles');
    add_line(m, srcPort, dst.Inport(1));
end

function s = pulisci(s)
    s = strtrim(regexprep(s, '\s+', ' '));
end

function v = dati(ts)
    v = double(squeeze(ts.Data));  v = v(:);
end

function x = ultimo(ts)
    v = dati(ts);
    if isempty(v), x = 0; else, x = v(end); end
end

function [m, mx] = mediaTempo(ts, Tstop)
    % media pesata nel tempo di un segnale a gradini (n = 0 prima del primo evento)
    t = ts.Time(:);  v = dati(ts);
    if isempty(t), m = 0; mx = 0; return; end
    dt = diff([t; Tstop]);
    m  = sum(v .* dt) / Tstop;
    mx = max(v);
end

