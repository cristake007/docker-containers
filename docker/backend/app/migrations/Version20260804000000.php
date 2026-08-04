<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

final class Version20260804000000 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Creates foundational application metadata used by readiness checks.';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE application_metadata (metadata_key VARCHAR(100) NOT NULL, metadata_value TEXT NOT NULL, updated_at TIMESTAMP(0) WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL, PRIMARY KEY (metadata_key))');
        $this->addSql("INSERT INTO application_metadata (metadata_key, metadata_value) VALUES ('schema_version', '1')");
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE application_metadata');
    }
}
