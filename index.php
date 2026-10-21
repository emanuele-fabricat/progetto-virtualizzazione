/*<?php
session_start();
global $db = new mysqli("mio-mariadb.progetto.svc.cluster.local", "admin", "Admin1234!", "prova", 3307);
if ($db->connect_error) {
            die("Connection failed: " . $db->connect_error);
        }
function getNames() {
	$query = "SELECT c.nome FROM citta c ORDER BY c.id";
	$stmt = $db->prepare($query);
	$stmt->execute();
	$result = $stmt->get_result();
	
	return $result->fetch_all(MYSQLI_ASSOC);
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>ECCOCI GHINI</title>
</head>
<body>
    <ol>
    	<?php
        foreach(getNames() as $name):
        ?>
        <li><?php echo $name['nome']; ?></li>
        <?php endforeach;?>
    </ol>
</body>*/
<?php
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$db = new mysqli(
    getenv('DB_HOST') ?: 'mio-mariadb.progetto.svc.cluster.local',
    getenv('DB_USER'),
    getenv('DB_PASSWORD'),
    getenv('DB_NAME'),
    3306
);
$db->set_charset('utf8mb4');

function getNames(mysqli $db): array
{
    $stmt = $db->prepare(
        'SELECT c.nome FROM citta AS c ORDER BY c.id'
    );
    $stmt->execute();
    $names = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    return $names;
}
?>
<!DOCTYPE html>
<html lang="it">
<head>
    <meta charset="UTF-8">
    <title>ECCOCI GHINI</title>
</head>
<body>
    <ol>
        <?php foreach (getNames($db) as $row): ?>
            <li><?= htmlspecialchars($row['nome'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?></li>
        <?php endforeach; ?>
    </ol>
</body>
</html>
