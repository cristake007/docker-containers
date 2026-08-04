<?php

namespace App\Controller;

use App\Entity\User;
use Symfony\Bundle\SecurityBundle\Security;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Lets the frontend discover whether the BEARER cookie it's holding still
 * identifies a logged-in user, without needing a GraphQL round trip.
 */
final class MeController
{
    public function __construct(private readonly Security $security)
    {
    }

    #[Route('/api/me', name: 'api_me', methods: ['GET'])]
    public function __invoke(): JsonResponse
    {
        $user = $this->security->getUser();
        if (!$user instanceof User) {
            return new JsonResponse(['message' => 'Not authenticated.'], 401);
        }

        return new JsonResponse(['email' => $user->getEmail()]);
    }
}
