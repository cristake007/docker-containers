<?php

declare(strict_types=1);

namespace App\Controller;

use Doctrine\DBAL\Connection;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Throwable;

final class ReadinessController
{
    #[Route(path: '/readyz', name: 'app_readiness', methods: ['GET'])]
    public function __invoke(Connection $connection): Response
    {
        try {
            $schemaVersion = $connection->fetchOne(
                "SELECT metadata_value FROM application_metadata WHERE metadata_key = 'schema_version'",
            );

            if ($schemaVersion !== '1') {
                throw new \RuntimeException('The foundational migration is not active.');
            }

            return new Response(
                "ready\n",
                Response::HTTP_OK,
                [
                    'Cache-Control' => 'no-store',
                    'Content-Type' => 'text/plain; charset=utf-8',
                    'X-Application-Readiness' => 'database',
                ],
            );
        } catch (Throwable) {
            return new Response(
                "not ready\n",
                Response::HTTP_SERVICE_UNAVAILABLE,
                [
                    'Cache-Control' => 'no-store',
                    'Content-Type' => 'text/plain; charset=utf-8',
                ],
            );
        }
    }
}
