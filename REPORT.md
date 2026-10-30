# Grupas praktiskais darbs: LP steikings un GROUP tokens

**Mācību kurss**: Blokķēdes un viedie līgumi (BIS)  
**Tīkls**: Ethereum Sepolia Testnet  
**DEX protokols**: Uniswap v2  
**GroupFarm Līgums**: [`0x6a5e91E3cDD3Ace2D656dF516463bEB8201bFBeB`](https://sepolia.etherscan.io/address/0x6a5e91E3cDD3Ace2D656dF516463bEB8201bFBeB)  
**Kopējais tokens (GROUP_FISH / GFSH)**: [`0x823C8A3989b1Fa1b982bFb7bC6b569694D1bEEDB`](https://sepolia.etherscan.io/address/0x823C8A3989b1Fa1b982bFb7bC6b569694D1bEEDB)

---

## 1. Līgumu un Tokenu Adreses

### 1.1. Dalībnieku Personīgie Tokeni (Sepolia)
| Dalībnieks | Tokena Nosaukums | Simbols | Līguma Adrese | Decimālzīmes |
|---|---|---|---|---|
| **1. Dalībnieks (tokjv)** | tokjv | `TOK` | [`0x4041680C805A8e9D3f2c96AA5DfF81b15f1cCdD8`](https://sepolia.etherscan.io/address/0x4041680C805A8e9D3f2c96AA5DfF81b15f1cCdD8) | 18 |
| **2. Dalībnieks (Amanda)** | TOKEN_AMANDA | `TAMA` | [`0xd9C0f7C3f90d510b7be94a2dda5f85C2D5dBf0D9`](https://sepolia.etherscan.io/address/0xd9C0f7C3f90d510b7be94a2dda5f85C2D5dBf0D9) | 18 |
| **3. Dalībnieks (Amir)** | TOKEN_AMIR | `TAMR` | [`0xdb34824b51eC5e39e4dD1f226c27679d849FfA0d`](https://sepolia.etherscan.io/address/0xdb34824b51eC5e39e4dD1f226c27679d849FfA0d) | 18 |

### 1.2. Grupas Kopīgais Tokens (GROUP_FISH)
- **Nosaukums**: `GROUP_FISH`
- **Simbols**: `GFSH`
- **Adrese**: [`0x823C8A3989b1Fa1b982bFb7bC6b569694D1bEEDB`](https://sepolia.etherscan.io/address/0x823C8A3989b1Fa1b982bFb7bC6b569694D1bEEDB)
- **Kopējā Emisija**: 100 000 000 GFSH
- **Decimālzīmes**: 18
- **Sadalījums**:
  - Pool 0 (TAMA / GFSH) sākuma likviditāte: 100 000 GFSH
  - Pool 1 (TAMR / GFSH) sākuma likviditāte: 100 000 GFSH
  - Pool 2 (tok / GFSH) sākuma likviditāte: 100 000 GFSH
  - GroupFarm steikinga atlīdzību fonds: 120 000 GFSH
  - Rezerve (deployer makā `0x8898...Ea70`): 99 580 000 GFSH

### 1.3. Uniswap v2 Likviditātes Pāri (Pūli)
| Pūla ID | Pāris | LP Tokena Adrese | Rezerves (Sepolia v2) |
|---|---|---|---|
| **Pool 0** | GFSH / TAMA | [`0xdae8a0e7b21d796287F2086021a32FdE49E6a75a`](https://sepolia.etherscan.io/address/0xdae8a0e7b21d796287F2086021a32FdE49E6a75a) | 100 000 GFSH / 100 000 TAMA (Sākuma cena: 1.0) |
| **Pool 1** | GFSH / TAMR | [`0x8dEdc40990F83B38DE95060f9E6A2dA04193AFDB`](https://sepolia.etherscan.io/address/0x8dEdc40990F83B38DE95060f9E6A2dA04193AFDB) | 100 000 GFSH / 200 000 TAMR (Sākuma cena: 0.5) |
| **Pool 2** | tok / GFSH | [`0x113E5C416BaABdc66d2986aCB6e5A43452734eB1`](https://sepolia.etherscan.io/address/0x113E5C416BaABdc66d2986aCB6e5A43452734eB1) | 50 000 TOK / 100 000 GFSH (Sākuma cena: 2.0) |

### 1.4. GroupFarm Viedais Līgums
- **Adrese**: [`0x6a5e91E3cDD3Ace2D656dF516463bEB8201bFBeB`](https://sepolia.etherscan.io/address/0x6a5e91E3cDD3Ace2D656dF516463bEB8201bFBeB)
- **Īpašnieks (Owner)**: `0x8898aaBCf31f5CD257d403453F5F16279562Ea70`
- **Izvietošanas transakcija**: [`0x79a0d23a1915c5759a8f46b0fe773e6de5c17248636299c43580b9bf7587b221`](https://sepolia.etherscan.io/tx/0x79a0d23a1915c5759a8f46b0fe773e6de5c17248636299c43580b9bf7587b221)
- **Kompilatora versija**: Solidity `^0.8.20` (EVM target: Shanghai / London, optimizer enabled, 200 runs)
- **Izmantotās bibliotēkas**: `@openzeppelin/contracts` (v5.x): `IERC20`, `SafeERC20`, `Ownable`, `ReentrancyGuard`

---

## 2. Sistēmas Arhitektūra un Atlīdzību Aprēķins

### 2.1. Formula un Akumulators (Reward-Per-Share)
GroupFarm līgumā netiek izmantoti `for` cikli pār lietotājiem, tādējādi gāzes patēriņš ir $O(1)$ un novērš DoS ievainojamības.
Uzkrātais atlīdzību rādītājs katram pūlam tiek rēķināts kā:

$$\Delta accRewardPerShare = \frac{\Delta t \cdot \text{rewardPerPool} \cdot 10^{18}}{\text{duration} \cdot \text{totalStaked}}$$

Lietotāja peļņa starp stāvokļu atjauninājumiem:
$$\text{earned}(u) = \frac{\text{staked}_u \cdot (accRewardPerShare - paidAcc_u)}{10^{18}}$$

### 2.2. Galvenie Mehānismi
1. **Pilna priekšfinansēšana**: `startSession()` var izsaukt tikai vienreiz un tikai tad, kad līguma GFSH atlikums sasniedz vismaz 120 000 tokenu.
2. **Tukšā pūla budžeta dzēšana**: Ja pūlā nav neviena steikotāja ($\text{totalStaked} = 0$), laika sprīdis tiek izlaists, nepārliekot šīs atlīdzības uz nākamajiem dalībniekiem.
3. **Droša uzskaite**: `stake()` un `withdraw()` vispirms iegrāmato līdz šim nopelnīto (`_book()`), un tikai tad izmaina dalībnieka un pūla bilanci.
4. **Dubultas izmaksas novēršana**: `_pay()` iestata `u.rewards = 0` pirms tokenu pārskaitījuma.
5. **Nošķirtas bilances**: Steikotā LP pamatsumma (`totalStaked`) un atlīdzību rezerve tiek glabātas un uzskaitītas pilnīgi neatkarīgi.

---

## 3. Savstarpējo Testu Rezultāti (9/9 Nokārtoti)

Testi tika izpildīti ar Hardhat integrēto Solidity testu vidi (`test/GroupFarm.t.sol`), pilnībā pārbaudot visus 9 uzdevuma specifikācijas scenārijus:

| Nr. | Tests | Sagaidāmais rezultāts | Testa Statuss |
|---|---|---|---|
| 1 | `test1_SingleStakerReceivesFullReward` | Viens steikotājs saņem visu pūla atlīdzību par savu aktīvās dalības laiku (1000 GFSH par 3 min). | **PASSED** (✔) |
| 2 | `test2_LateJoinerReceivesZeroPriorReward` | Vēlāk pievienojies dalībnieks nesaņem atlīdzību par laiku pirms ienākšanas (0 pirms t=180, 50% pēc tam). | **PASSED** (✔) |
| 3 | `test3_MultiPoolIndependence` | Katra pūla uzskaite ir neatkarīga; citas pūla aktivitāte neietekmē paralēlā pūla emisiju. | **PASSED** (✔) |
| 4 | `test4_PartialWithdrawReducesAccrual` | Pēc 50% LP izņemšanas turpmākā atlīdzība proporcionāli samazinās atbilstoši mazākai pūla daļai. | **PASSED** (✔) |
| 5 | `test5_RepeatedClaimGivesZero` | Jau izņemtu atlīdzību nevar saņemt atkārtoti; atkārtots tūlītējs claim izmaksā 0. | **PASSED** (✔) |
| 6 | `test6_EmptyPoolTimeBudgetSkipped` | Kamēr pūls ir tukšs, tā laika budžets netiek piešķirts nākamajam ienācējam. | **PASSED** (✔) |
| 7 | `test7_CampaignEndStopsAccrualAllowsWithdrawAndClaim` | Pēc 120 min kampaņas beigām jaunas atlīdzības neuzkrājas, bet LP izņemšana un claim turpina darboties. | **PASSED** (✔) |
| 8 | `test8_InvalidPoolReverts` | Nereģistrētu pūla ID vai neatļautu tokenu nevar iesniegt kā steiku (`InvalidPool()` kļūda). | **PASSED** (✔) |
| 9 | `test9_FundConservationInvariant` | Izmaksāto un vēl pienākošos atlīdzību summa nepārsniedz finansēto budžetu (120 000 GFSH). | **PASSED** (✔) |

---

## 4. Tīmekļa Lietotne (Frontend)

Izstrādāta viena neatkarīga HTML/JavaScript lietotne `index.html`:
- **MetaMask & Tīkla Pārbaude**: Automātiski nosaka un piedāvā pārslēgties uz Ethereum Sepolia (Chain ID `11155111` / `0xaa36a7`).
- **Kopējais Kampaņas Panelis**:
  - Reāllaika laika atskaite (countdown) līdz sesijas beigām.
  - Kampaņas statuss: `NOT FUNDED`, `READY TO START`, `ACTIVE` vai `ENDED`.
  - Progresa josla un kopsavilkums par kopējo atlīdzību fondu un lietotāja maku.
  - Globāla poga **Claim All Pools**.
- **Pūlu Kartītes**:
  - Trīs atsevišķas interaktīvas kartītes (Pool 0: GFSH/TAMA, Pool 1: GFSH/TAMR, Pool 2: tok/GFSH).
  - Rāda pūla kopējo LP apjomu, lietotāja makā esošo LP, steikoto LP un nopelnītos GFSH.
  - Ievades lauks ar **Max** pogu.
  - Pogas: **Approve**, **Stake**, **Withdraw**, **Claim**.
  - Tiešās saites uz Sepolia Etherscan un Uniswap v2 likviditātes pārvaldību.
- **Transakciju Stāvokļu Paziņojumi**:
  - Precīzs stāvoklis: Gaida parakstu -> Transakcija nosūtīta (ar Etherscan saiti) -> Gaida bloka apstiprinājumu -> Veiksmīgi izpildīta vai noraidīta.
- **Admin Panelis**:
  - Automātiski atpazīst līguma īpašnieka adresi (`0x8898...Ea70`) un parāda finansēšanas pogu (120 000 GFSH) un `startSession()` pogu.

---

## 5. Tehniskais un Ekonomiskais Izvērtējums

### 5.1. Atlīdzību Izcelsme (Reward Origin)
GroupFarm līgumā atlīdzības nerodas no jaunas emisijas (minting inflācijas), bet gan no iepriekš izveidota un fiksēta atlīdzību fonda (120 000 GFSH), kas kampaņas sākumā tiek pārskaitīts un iesaldēts viedā līguma balansā. Līgums pats nesatur `mint` funkciju, tādējādi atlīdzību izmaksa nevar palielināt kopējo tokenu skaitu un ir pilnībā nodrošināta ar rezervi.

### 5.2. Papildu Steikotāju Ietekme (Dilution Effect)
Katra pūla laika atlīdzības ātrums ir konstants ($R = \frac{40\,000}{7\,200} \approx 5.555$ GFSH sekundē jeb 1000 GFSH trijās minūtēs). Kad pūlam pievienojas jauni dalībnieki, kopējais steikotais LP apjoms ($S$) pieaug. Tā rezultātā viena konkrēta dalībnieka nopelnīto tokenu daļa $\frac{s_i}{S}$ proporcionāli samazinās. Ja viens dalībnieks steiko 100 LP un pievienojas otrs ar 300 LP, pirmā dalībnieka ienesīgums samazinās no 100% līdz 25% no pūla emisijas.

### 5.3. Tokenu Īpašnieku Tiesību Riski (Centralization & Governance Vectors)
Lai gan pats `GroupFarm` līgums ir veidots bez "rug-pull" funkcijām (īpašnieks nevar atsaukt dalībnieku LP vai piesavināties atlīdzības), sistēmas drošība ir atkarīga arī no pamatā esošajiem ERC-20 tokeniem. Ja kādam personīgajam tokenam īpašnieks saglabā tiesības veikt nekontrolētu papildu emisiju (`mint`), ieviest pārskaitījumu nodokļus (`transfer tax`) vai bloķēt adreses (`blacklist`), šāds īpašnieks var vienpusēji manipulēt ar AMM pūla rezervēm un izsūkt likviditāti.

### 5.4. Nominālā Cena vs Reālā Likviditāte
Augsta nominālā cena decentralizētajā biržā (AMM) nav projekta kvalitātes vai vērtības rādītājs. Uniswap v2 cenrādis tiek noteikts tīri ar rezervju attiecību $x \cdot y = k$. Ja pūlā ir iemaksāts niecīgs likviditātes apjoms, pat ar nelielu darījumu cenu var mākslīgi uzskrūvēt līdz astronomiskiem skaitļiem. Taču mēģinot pārdot pat nelielu daudzumu šo tokenu, rodas milzīgs cenas kritums (*slippage*). Tokenu vērtība realitātē ir atkarīga no reālās likviditātes dziļuma un ārējā pieprasījuma, nevis no matemātiskas attiecības mazā testa pūlā.
