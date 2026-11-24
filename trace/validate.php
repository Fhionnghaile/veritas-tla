<?php
/**
 * Trace validation: does the REAL Veritas verifier agree with the TLA+ model in every
 * reachable state?
 *
 *   php trace/validate.php <states.dump> <path/to/veritas/src>
 *
 * <states.dump> is TLC's own dump of every distinct reachable state of VeritasRevocation
 * (`java tlc2.TLC -dump states.dump -config correct.cfg VeritasRevocation.tla`).
 * For every state and every credential, the model's decision (Accepts(c) with both guards on)
 * is compared with what the PHP verifier returns for a real, signed credential set up to match
 * that state: model time t -> unix BASE+t, exp[c] -> BASE+exp[c], revoked -> a revocation list,
 * and "not issued" -> a credential signed by a key the verifier does not trust.
 * Exits non-zero on any disagreement and prints the first few.
 */
declare(strict_types=1);
[$dump, $src] = [$argv[1] ?? '', rtrim($argv[2] ?? '', '/')];
if (!is_readable($dump) || !is_dir($src)) { fwrite(STDERR, "usage: php trace/validate.php <states.dump> <veritas/src>\n"); exit(2); }
foreach (['Credential', 'Issuer', 'Verifier', 'Revocation'] as $f) { require "$src/$f.php"; }
use Veritas\{Issuer, Verifier, InMemoryRevocation};

const BASE = 1794744000;                       // any fixed instant; only differences matter
$trusted   = new Issuer(str_repeat("\x01", 32)); // TEST-ONLY keys, generated here, never shipped
$untrusted = new Issuer(str_repeat("\x02", 32));
$pub = \Veritas\Credential::b64urlEncode(sodium_crypto_sign_publickey(sodium_crypto_sign_seed_keypair(str_repeat("\x01", 32))));

// --- parse TLC's dump format: "State N:" then "/\ var = value" lines ---
$states = []; $cur = null;
foreach (file($dump, FILE_IGNORE_NEW_LINES) as $ln) {
    if (preg_match('/^State \d+:/', $ln)) { if ($cur) $states[] = $cur; $cur = []; continue; }
    if ($cur !== null && preg_match('/^\/\\\\ (\w+) = (.*)$/', trim($ln), $m)) { $cur[$m[1]] = trim($m[2]); }
}
if ($cur) $states[] = $cur;
$set = fn(string $v): array => $v === '{}' ? [] : array_map('trim', explode(',', trim($v, '{}')));
$fun = function (string $v): array { // (c1 :> 3 @@ c2 :> 1)  or  [c1 |-> 3, c2 |-> 1]
    preg_match_all('/(\w+)\s*(?::>|\|->)\s*(\d+)/', $v, $m, PREG_SET_ORDER);
    $o = []; foreach ($m as $x) { $o[$x[1]] = (int)$x[2]; } return $o;
};

$checked = 0; $agree = 0; $bad = [];
foreach ($states as $i => $s) {
    $t = (int)$s['time']; $issued = $set($s['issued']); $revoked = $set($s['revoked']); $exp = $fun($s['exp']);
    foreach (array_keys($exp) as $c) {
        $model = in_array($c, $issued, true) && $t <= $exp[$c] && !in_array($c, $revoked, true);
        $claims = ['iss' => 'did:web:derrytraining.com', 'kid' => 'k1', 'sub' => 's', 'skill' => 'docker',
                   'level' => 'Advanced', 'iat' => BASE, 'exp' => BASE + $exp[$c], 'jti' => $c];
        $token = (in_array($c, $issued, true) ? $trusted : $untrusted)->issue($claims);
        $real = (new Verifier($pub, new InMemoryRevocation($revoked)))->verify($token, BASE + $t);
        $checked++;
        if ($real['valid'] === $model) { $agree++; continue; }
        $bad[] = sprintf('state %d: time=%d issued=%s exp[%s]=%d revoked=%s -> model %s, PHP %s (%s)',
            $i + 1, $t, $s['issued'], $c, $exp[$c], $s['revoked'],
            $model ? 'ACCEPT' : 'reject', $real['valid'] ? 'ACCEPT' : 'reject', $real['reason']);
    }
}
printf("%d reachable states x credentials = %d decisions checked against the real verifier\n", count($states), $checked);
printf("agree: %d   disagree: %d\n", $agree, count($bad));
foreach (array_slice($bad, 0, 6) as $b) { echo "  $b\n"; }
if (count($bad) > 6) { printf("  ... %d more\n", count($bad) - 6); }
echo $bad ? "TRACE VALIDATION FAILED: model and implementation disagree\n" : "TRACE VALIDATION PASS: the PHP verifier matches the model in every reachable state\n";
exit($bad ? 1 : 0);
