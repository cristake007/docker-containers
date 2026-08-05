<?php

namespace App\Repository;

use App\Entity\User;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Bridge\Doctrine\Security\User\UserLoaderInterface;
use Symfony\Component\Security\Core\User\UserInterface;

/**
 * @extends ServiceEntityRepository<User>
 */
class UserRepository extends ServiceEntityRepository implements UserLoaderInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, User::class);
    }

    /**
     * Case-insensitive lookup by email. The only write path (see
     * App\Command\BootstrapAdminCommand) always stores a lowercased,
     * trimmed email, so this keeps login independent of the exact casing a
     * user happens to type.
     */
    public function loadUserByIdentifier(string $identifier): ?UserInterface
    {
        return $this->createQueryBuilder('u')
            ->andWhere('LOWER(u.email) = :identifier')
            ->setParameter('identifier', mb_strtolower(trim($identifier)))
            ->getQuery()
            ->getOneOrNullResult();
    }
}
